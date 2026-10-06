# `checks/e2e.sh`'s ROOT WAS NOT THE REPOSITORY, AND THE PIN THAT GUARDED IT WAS NOT DELETED

Unit `.agents/slop/e2esh/`. One job: `checks/e2e.sh` resolves its paths against
`/Users/cyberistic/src/tries`, the repo's PARENT, and the sibling unit handed over the conclusion
that deleting `checks/e2e.py`'s `BODY_SHA` is the clean unblock. **That conclusion is not supported by
the measurement, and this is the measurement.** Owned: `checks/e2e.sh`, `checks/e2e.py`,
`.agents/slop/e2epy/oracle-e2e.sh`, this directory. Compiler Bend 2.0.34. Not committed.

## 1. WHAT `checks/e2e.sh` RESOLVED TO, IN THREE PLACES

`checks/e2e.sh:33` was `ROOT=$(cd "$(dirname "$0")/../.." && pwd)`, written while the file lived at
`.agents/slop/` and left behind when it moved to `checks/`, one level shallower. `.agents/slop/e2esh/
resolve.py`, from `/`, by absolute path:

```
1 here, by absolute $0
  $0    /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks/e2e.sh
  cwd   /
  ROOT  /Users/cyberistic/src/tries
  -> WRONG ROOT

2 copied tree, by absolute $0        (4 levels deep, under $TMPDIR, a different name)
  $0    .../e2esh-copy/checks/e2e.sh
  cwd   /
  ROOT  .../a/b/c/d
  -> WRONG ROOT

0 of 2 invocation(s) resolved to the tree that holds pyproject.toml
```

**THE THIRD PLACE IS THE ONE THAT MATTERS AND IT IS NOT A SEPARATE ROW.** A `$0`-derived root is
supposed to be independent of the cwd, so "and from a foreign CWD" is not a third location -- it is
the property that distinguishes a root computed from `$0` from one computed from `pwd`, and both rows
above already run with `cwd=/`. Before the fix, `cd "$ROOT"` into `/Users/cyberistic/src/tries`
**SUCCEEDED**, because that directory exists: nothing refused, and the run proceeded.

**AND WHAT THAT MEANT FOR THE SEVEN STAGES** (`.agents/slop/e2esh/stagepaths.py`, every path checked
under both roots, the old root's line read from `git show HEAD:checks/e2e.sh` rather than
transcribed):

```
OLD root -> /Users/cyberistic/src/tries      NEW root -> …/2026-09-30-tinybendygrad

stage                      path                                    OLD root    NEW root
1 e2e_mm.py                .venv/bin/python                        ABSENT      present
2 ./bin/bend               bin/bend                                ABSENT      present
3 e2e_mm_run.mjs           .agents/slop/e2e_mm_run.mjs             ABSENT      present
4 e2e_mm_gate.py           .agents/slop/e2e_mm_gate.py             ABSENT      present
5 opsbend-milestone.sh     .agents/slop/opsbend-milestone.sh       ABSENT      present
6 run-port-mm.sh           .agents/slop/e2e_port/run-port-mm.sh    ABSENT      present
7 run-f64.sh               .agents/slop/f64/run-f64.sh             ABSENT      present
- runs/e2e                 runs                                    ABSENT      present
- pyproject.toml           pyproject.toml                          ABSENT      present

0 of 9 path(s) resolve under both roots; 9 changed
```

**ALL NINE ARE ABSENT UNDER THE OLD ROOT.** The old run did not measure the repository and did not
know it. Its live exit status, reproduced on HEAD's whole body in a scratch tree whose `../..` exists
and is not a repo:

```
== 1/4 oracle (CPython tinygrad, DEV=CPU)
<scratch>/before/.venv/bin/python: No such file or directory     rc=1
```

So `exit 1` was a **`command not found` in stage 1** -- the seven stages' own verdict lines never
existed, and `--- verdicts:` never printed. One stage of measurement happened and it measured the
absence of a file.

## 2. THE PIN IS LOAD-BEARING. IT IS NOT A COMMENT IN A COMMENT.

`.agents/slop/e2esh/history.py` reads `BODY_SHA` as `checks/e2e.py` held it **at each commit that
touched `checks/e2e.sh`**, and compares it to the file's sha256 there -- `git show <rev>:<path>` for
both, so a dirty tree cannot manufacture or hide a row:

```
3 commits touched checks/e2e.sh
3ed5ab069  pin MOVED with the file
713deb273  pin MOVED with the file
1535a75f4  no pin at this commit
commits that changed checks/e2e.sh without moving BODY_SHA: 0
```

**ZERO.** So the pin has never been unpaid for. But that is a fact about **DISCIPLINE**, not about
whether the pin can see anything, and those are different questions, so it was asked directly
(`.agents/slop/e2esh/plant.py`, live tree restored from the bytes read at entry, asserted afterwards by
sha256 AND by length):

| plant | `oracle_drift()` | `checks/e2e.py` | stdout fidelity |
|---|---|---|---|
| unplanted | `[]` | — | `0 of 1 disagree` |
| **A one comment line, no code** | fires | **`rc=3`**, `== 1/4 oracle` never printed | `1 of 1 disagree` |
| **B one root MARKER dropped** | fires | **`rc=3`**, `== 1/4 oracle` never printed | `1 of 1 disagree` |

**A CHANGE TO `checks/e2e.sh` FAILS SOMETHING, AND IT IS THIS GATE.** Plant B is the one that matters:
it changes the subject's BEHAVIOUR -- drop `pyproject.toml` from the assertion and the preamble would
accept a tree that is not this repository -- and the pin catches it. **Deleting `BODY_SHA` would have
deleted the only thing that notices.**

## 3. THE THING THAT WAS BELIEVED INSTEAD, MEASURED FALSE

The brief's alternative is that stdout fidelity already covers the live shell, so the text pin is
redundant with it and belongs a layer down. **It does not.** `diff.py` compares `checks/e2e.py`
against the **frozen oracle** and never reads `checks/e2e.sh` -- `ORACLE, PORT =
".agents/slop/e2epy/oracle-e2e.sh", "checks/e2e.py"`. Under both plants it reported `1 of 1 disagree`,
and the artifacts say where the disagreement was:

```
.agents/slop/e2epy/artifacts/plant-no-node.port.err   (2 lines, BOTH of them ORACLE DRIFT)
.agents/slop/e2epy/artifacts/plant-no-node.port.out   (EMPTY)
```

**THE PIN IS INSIDE THE MEASUREMENT, SO THE MEASUREMENT CANNOT SEE PAST IT.** Fidelity is not a
second observer of the live shell; it is a victim of the pin. There is no stdout-level guard to move
the pin down to.

**THE SIBLING UNIT'S PREMISE, CHECKED.** `.agents/slop/shells/README.md` §"`checks/e2e.sh` CANNOT BE
FIXED FROM HERE" concludes that deleting `checks/e2e.sh` is the clean unblock, and rests on the pin's
comment saying the check "is deliberately NOT a failure when the file is absent". That is true of the
comment and it is not what the pin does. Question (3) fires on a **present** file that **changed**,
which is the ordinary case; absence is a different branch, and §2's plants are in the other one.

## 4. WHAT CHANGED, AND WHY THIS IS THE RIGHT LAYER

`checks/e2e.sh:32-43` -- the root is ASSERTED, in the form the other sixteen `checks/*.sh` use:

```sh
_d=${0%/*}; case $_d in "$0") _d=.;; esac
ROOT=$(cd "$_d/.." && pwd)
[ -f "$ROOT/pyproject.toml" ] && [ -d "$ROOT/tinybendygrad" ] ||
  { echo "$0: not at the repo root (pwd $ROOT)" >&2; exit 2; }
cd "$ROOT"
```

`checks/e2e.sh`'s exit-status table, `2` is now documented as **two** refusals that share a status
because the number cannot tell them apart and both name themselves on stderr.

`checks/e2e.py` -- the pins moved, and `ORACLE_EDIT` is now a MULTI-LINE pair. It is still ONE edit:
`diff.py` drives the oracle against a fixture tree through `E2E_ROOT`, a fixture has no
`pyproject.toml` for the assertion to find, so the oracle carries the redirect and not the assertion.
The shell carries the assertion and no redirect, because nothing runs it against a fixture. The
invariant is still **proved, not asserted**: `revert(oracle) == checks/e2e.sh`, byte for byte, checked
by `.agents/slop/e2esh/refreeze.py` with `difflib` and `hashlib` -- different machinery from the
writer that produced the pair. Six `checks/e2e.sh:<line>` citations were repointed at the fixed file;
all six were **already stale at HEAD** (232 vs 247, 75-83 vs 82-88, 39-56 vs 42-59, 104-112 vs
110-118), so this is a repair, not drift introduced here.

**THE LAYER, STATED.** A pin over a file's TEXT is coupled to every comment in it; a pin over what the
file **PRODUCES** is not. `checks/e2e.sh`'s subject is its root, and its root is now **asserted by
the file itself** -- so the wrong root is refused at the root, before any stage, by the script, in a
message that names the directory it reached. That is a pin that guards the subject rather than the
prose, and it lives in the file rather than in another file's hash. **The text pin stays, because it
is what makes the assertion's subject auditable** -- a file nobody diffs is a file nobody can claim is
frozen -- and it costs one sha on the commit that changes the file, which is a price that can be paid,
against the alternative of a guard that fires on a comment and therefore can never be paid for at all.

## 5. THE TWO COLUMNS

`.agents/slop/e2esh/repro.py` -- the subject is the root, so the columns run the file's own ROOT
PREAMBLE (cut out by shape, not transcribed) rather than the seven stages underneath it. Stage 6 is
recorded green on one run of an unmodified tree and red on the next, so a column whose verdict
depended on it would be a column measuring the machine.

```
COLUMN 1  where it lives, absolute $0, from /
  $0    …/2026-09-30-tinybendygrad/checks/e2e.sh
  exit  0
  ROOT  …/2026-09-30-tinybendygrad
  -> OK: the repo

COLUMN 2  moved one deeper, absolute $0, from /
  $0    …/2026-09-30-tinybendygrad/checks/deeper/e2e.sh
  exit  2
  ROOT  (unprinted: the refusal exits before it)
  said  …/checks/deeper/e2e.sh: not at the repo root (pwd …/2026-09-30-tinybendygrad/checks)
  markers missing: none
  -> OK: refused, and named the directory it reached

CONTROL -- the belt's own direction of failure
  column 2's check, file NOT relocated: exit 0, did NOT refuse
  -> OK: the two disagree, so the check tells them apart

plant removed: OK
both columns hold
```

**THE MARKER IS READ WITH THREE `in` TESTS OVER RAW SUBSTRINGS**, not one regex: `not at the repo
root`, `(pwd `, and the reached directory. The `[A-Za-z0-9_.-]*`-ate-a-full-stop lesson applies
directly -- a belt built out of the writer's own tokenizer inherits its blind spot and calls the plant
unmoved. **AND `$ROOT` IS NOT ASSERTED ON COLUMN 2**, because the refusal `exit 2`s before anything can
print it, which is exactly why the reached directory is carried in the MESSAGE. A first cut asserted
`ROOT == <reached>` there, and reported `DID NOT REFUSE` for a run that had refused correctly and said
so; it would also have passed a preamble that refused for the wrong reason and named the wrong
directory. The harness failing is in this file's own history rather than described here.

## 6. THE REAL RUN, NOT ONLY THE PREAMBLE

`/bin/sh /abs/path/checks/e2e.sh`, invoked from `/`:

```
rc=4
  stage 6 port (matmul THROUGH the port, no Node): PASS
  stage 7 f64 (double through the port, no Node): SKIP -- run-f64.sh refused: its substrate is cold
--- verdicts: 0 failed, 1 skipped ---
```

**rc 4, NOT rc 0, AND THE DIFFERENCE IS NOT MINE**: stage 7 is the pre-existing skip whose cause
`.agents/slop/skipexit/FINDINGS.md` §7 traced to a DELETED FIXTURE (`cstyle-live/port.txt` is absent
at that path in every commit), which is neither retryable nor this unit's to regenerate. Stage 6 was
green this run, which is the run-to-run variation the docstring records. Both statuses are printed
separately and neither is retried into a different answer.

## 7. FIDELITY, BEFORE AND AFTER

`.agents/slop/e2epy/diff.py --sets live` plus all eight plants, after the fix:

```
0 of 9 set(s) disagree
```

`live` and every one of `plant-pass`, `plant-passskip`, `plant-refuse`, `plant-no-node`,
`plant-no-zsh`, `plant-thin`, `plant-deadbend`, `plant-stage1red` report per-stage verdict lines
equal, all stage blocks `IDENTICAL`, and `stdout`/`stderr` `IDENTICAL`. Before the fix the same driver
over the eight plants reported `0 of 8` (`skipexit/FINDINGS.md` §3), so **no set changed verdict**;
`live` is added because the fix is to a file `live` exercises. The re-frozen oracle's `E2E_ROOT`
redirect is what keeps the plants drivable -- an assertion in the oracle would refuse all eight,
which is a fixture tree with no `pyproject.toml`.

## 8. WHAT I COULD NOT SETTLE

- **Whether `checks/e2e.sh` should exist at all.** `checks/e2e.py` is its successor and
  `.agents/slop/e2e.sh` is a shim that `exec`s the Python. With the root fixed, the shell is a
  runnable second implementation of the same seven stages, which is the only thing the migration rule
  needs; with the pin paid, keeping it costs one sha per edit to it. This unit fixed it because that
  was the job, and the sibling unit's "delete it" remains a defensible call on a different question --
  how many implementations of the gate the project wants.
- **`2` now means two refusals.** The root assertion reuses `2`, which the table already gave to eight
  fruitless `bend` attempts. Both are "nothing was measured, no verdict lines", and both name
  themselves on stderr, so a caller needing to distinguish reads stderr rather than `$?`. A distinct
  status would be cleaner; `5` and `6` are `checks/bounded.py`'s and `4` is PASS-with-SKIP, and I did
  not want to spend a status on this without being asked.
- **Stage 6 was green once here.** One run is not a claim about its reproducibility, and
  `.agents/slop/skipexit/FINDINGS.md` §0 already measured `rc 1` then `rc 0` on one unmodified tree.
  I did not re-run the driver a second time over `live`, because `live` needs the machine to itself
  and three other units were running.
- **`.agents/slop/e2epy/artifacts/live.*` are rewritten** by any `diff.py --sets live` run, including
  this one. They are that driver's own output; no other unit's tree is touched.
- **The `checks/e2e.py` line citations were stale before this unit and are now right.** Six were
  repointed. There may be more that cite `checks/e2e.sh` by prose rather than by number; I did not
  sweep the whole repo for those.

## 9. FOUR HARNESS BUGS, ALL CAUGHT BY VACUITY REFUSALS, NONE BY READING

Recorded because the pattern is the point: in each case a check reported agreement while measuring
nothing, and each was found by the check being run against an input where it could not pass.

1. `sh -c '…; printf "$ROOT"'` leaves `$0` as the shell's own name, so `dirname $0` was `.` and
   **every invocation resolved to `/`** -- reported as a wrong root for the wrong reason. `$0` is now
   `sh -c`'s COMMAND NAME argument.
2. The resolution harness compared a COPIED TREE against *this* repo, so a correct copied tree was
   reported wrong for being a different tree. Each copy is now compared against the tree it lives in.
3. `stagepaths.py` evaluated the new root as a bare `ROOT=$(cd "$_d/.." && pwd)` line, which without
   the `$_d` line above it yields **`/`**; all nine paths then read ABSENT under BOTH roots and the
   summary said `0 changed` -- agreement from measuring nothing. It now runs the whole preamble and
   asserts the result is the repo before printing a table.
4. `repro.py`'s column 2 asserted `$ROOT == <reached>` on a run that correctly REFUSED, where `$ROOT`
   is unprintable by construction, and reported `DID NOT REFUSE`. The reached directory is in the
   stderr message, which is what the assertion exists to provide.