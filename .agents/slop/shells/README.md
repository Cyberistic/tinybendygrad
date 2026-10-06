# `checks/*.sh` AND WHERE THEY THINK THEY ARE

Fifteen of the eighteen `checks/*.sh` resolved a path relative to themselves and fourteen of
those resolved it wrong. Three were right. **One of the three was right by accident and had no
assertion**, so "right" and "correct" are different columns and only the second one survives a
`mv`.

## THE SHAPE OF A CORRECT SHIM, IN THREE LINES

```sh
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
```

Line 1 is `${0%/*}`, not `dirname`, because `dirname` is an external command for something the
shell does itself and a preamble that needs `PATH` reports "command not found" and then tries to
exec a relative path from wherever it happens to be. `checks/substrate-check.sh` carries the
measurement (with `dirname` off `PATH`, `e2e.sh` exits 126 and this one 127). The `case` is
there because `$0` with no slash leaves `${0%/*}` equal to `$0`; `case` returns 0 whether or not
a branch runs, and `[ .. ] && _d=.` returns **1** when the test fails, which is fatal under
`set -e` in five of these scripts.

Line 2 is `..` and not `../..` because `checks/` is ONE level below the root. `../..` is the
parent of the repo.

Line 3 is the whole point. **`cd` does not care where it lands.** Every one of these scripts had
a line that silently resolved against a directory that is not the repository, and the shell
carried on. Line 3 is what converts that from a wrong answer into a refusal.

## WHY TWO TRACKED MARKERS AND NOT ONE

`pyproject.toml` alone is satisfied by half a dozen unrelated checkouts; `tinybendygrad/` alone
is satisfied by a parent directory holding one copy. Both are tracked, so a clone has both, and
both exist at the root and nowhere else. The assertion therefore still holds in a fresh
`git worktree` — which is the whole test, because a root assertion that only holds on this
machine's checkout is the defect it is meant to catch.

## THE CENSUS, BEFORE AND AFTER

`checks/*.sh` only. `checks/*.py` is another unit's; the same arithmetic is read-only-reported
below because the class is not confined to shell.

| | before | after |
|---|---|---|
| files that COMPUTE a root | 16 | 16 |
| ... of those, from `$(dirname "$0")` relative to the script | 16 | 16 |
| ... of those, from an ABSOLUTE path to one machine's checkout | 2 (`mutate.sh`, `walk-mutate.sh`) | 0 |
| files that ASSERT the root holds the tree | **1** (`sb-gate.sh`) | **17** |
| files that resolve no root at all and inherit the caller's CWD | 1 (`gate.sh`) | 0 |

`plant.sh` is counted as neither: it DEMANDS `REPO` with no default, which is the right shape
— a caller who forgets gets an error rather than a guess — so it had no depth arithmetic to get
wrong. It gained the assertion on what it was handed.

## THE `.py` HALF OF THE SAME CLASS, AND A CORRECTION I HAD TO MAKE MYSELF

Read-only: `checks/*.py` belongs to another unit. The arithmetic, measured rather than argued:

| file | expression | resolves to | holds the tree? |
|---|---|---|---|
| `checks/abi_gate.py:50` | `HERE.parents[0]` | repo root | **yes**, and `refuse()` proves it at `:77` |
| `checks/abi4_gate.py:86` | `HERE.parents[0]` | repo root | **yes**, and `refuse()` proves it at `:114` |
| `checks/hermetic-census.py:33` | `HERE.parents[2]` | `/Users/cyberistic/src` | **no** |
| `checks/census.py:14` | `HERE.parents[2]` | `/Users/cyberistic/src` | **no** |
| `checks/bounded.py`, `substrate.py`, `no-strays.py`, `corpus-figure.py`, `disagree-gate.py`, `gates/retention-check.py` | `parents[1]` | repo root | yes |

I first wrote that the two abi gates were *also* one level shallow, on the strength of their
comment ("`parents[0]` ... IS the repo root") read against `Path(__file__).resolve().parents[0]`.
That reading was wrong and the comment is right, because the code is
`HERE = Path(__file__).resolve().parent` first: `HERE` is the `checks/` **directory**, and the
repo root is `parents[0]` *of the directory*. Both gates run and both prove their depth by
refusing. The two files that are genuinely wrong are the two still on `parents[2]`, and they
carry **no assertion at all** — which is the shape that broke `abi4_gate.py` in the first place.

**The two that need attention, and are not this unit's:**

- `checks/hermetic-census.py:33` — `REPO` is `/Users/cyberistic/src`, two levels above the repo.
- `checks/census.py:14` — puts `/Users/cyberistic/src` on `sys.path` to import `tinygrad`.

Both want `HERE.parents[0]`, and both should carry a `refuse()` on a tracked marker the way
`abi_gate.py:77` does. The reusable shape is already in the tree and in use, twice: **compute the
root, then prove it, before the first read.**

## THE INSTRUMENT, AND WHY IT RUNS THE SCRIPTS INSTEAD OF READING THEM

`rootcheck.sh` is the harness. It never reads a script's source; it executes the scripts in a
`git worktree` copy elsewhere, from a foreign CWD, and reads their exit status and output.

The reason is the harness bug this repo already paid for: a tokenizer hunting for `cd` with
`[A-Za-z0-9_.-]*` ate a full stop, and a second belt that **shared that tokenizer's assumption**
therefore missed the very thing it was hunting. A harness that executes needs no tokenizer at
all, so it cannot inherit one.

```
sh .agents/slop/shells/rootcheck.sh <tree> <seconds> <outdir>
```

Verdicts are `RAN`, `REFUSED` (the script's own assertion fired — a pass for this harness, since
a script that stops cannot silently succeed against the wrong tree), `WRONG-ROOT`, `DEAD`,
`ALARM` and `SKIP`. **`ALARM` is rc=142, which is the harness's own alarm, and is never counted
as a pass**: it proves only that the script got into its work. `SKIP` is never counted as a pass
either. The denominator is 18.

The gitignored prerequisites a script needs — `.venv/`, `references/`, `runs/`, `bin/bend` — are
linked into the worktree by the caller so that root-finding is the ONLY variable. `runs/` is a
real copy, not a symlink, because several scripts write into it and `runs/` belongs to another
unit.

## WHAT `mutate.sh` WAS, AND WHY IT IS GONE

Deleted rather than fixed. It did four things wrong at once, only one of which was the root:

1. `cd` to an absolute path into one machine's checkout.
2. Mutated `tinybendygrad/uop/spec.bend` **in the live tree**, in place.
3. Diffed against `/tmp/spec.gate.base`, which **it never creates and which does not exist**
   (`ls: /tmp/spec.gate.base: No such file or directory`). So even on this machine it could not
   report a row diff: `diff` against a missing file reports every line as moved. `/tmp` is also
   a shared global path that a concurrent process can clobber.
4. Ran five unbounded `bend` processes against that live file.

Its subject — one-string mutations of a port file, reported as the rows that moved — is covered,
with paired disarm and a live-tree digest assertion, by:

- `checks/lintable-gate.sh --plant` / `--disarm` (same shape, on `ops.bend`);
- `checks/plant.sh` (on `cstyle.bend`, hash-asserted before and after);
- `checks/walk-mutate.sh` (on `gradient.bend`, on a `$TMPDIR` copy);
- `.agents/slop/ops-501-mutate.py` (the direct successor; its header records why it refuses to
  write the live file, which is precisely what `mutate.sh` did).

Nothing referenced it. No `.md`, `.py`, `.sh` or `.toml` in the tree names it.

## `bin/bend` IS STILL BROKEN AND IS NOT THIS UNIT'S

```sh
exec bun /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/references/bend/bend2/main.ts "$@"
```

An absolute path into a gitignored checkout: it works on this machine, in this directory, and
nowhere else. **A clone inherits a launcher that cannot run.** The correct form already exists
one directory away, in `checks/bend`:

```sh
exec bun "$(dirname "$0")/../references/bend/bend2/main.ts" "$@"
```

## `checks/e2e.sh` IS FIXED, AND THE PIN WAS KEPT — SEE `.agents/slop/e2esh/`

This section used to say it could not be fixed from here, and recommended deleting the file. **Both
were checked, and the recommendation does not survive the measurement.** Kept as the record of what
was believed, and of what decided it.

`checks/e2e.py` pins the sha256 of `checks/e2e.sh`, so its root could not be edited without moving
that pin — that part was true, and `BODY_SHA` is still there. It resolved to
`/Users/cyberistic/src/tries`, the repo's PARENT, where `cd "$ROOT"` **SUCCEEDED**, so nothing
refused: **all nine of the seven stages' paths are ABSENT under that root**, and a live run of the
old body died in stage 1 on `command not found`, rc 1, with no verdict line ever printed.

**THE DELETION RECOMMENDATION RESTED ON THE PIN'S COMMENT** saying the check "is deliberately NOT a
failure when the file is absent". That is about a **missing** file. The pin fires on a file that is
present and **changed**, which is the ordinary case, and two plants measured it: appending one
comment line, and dropping one root MARKER, both gave `oracle_drift() != []` and `checks/e2e.py
rc=3` with `== 1/4 oracle` never printed. **Deleting the pin would have deleted the only thing that
notices.**

`diff.py` is not a second observer to move the pin down to: it compares the PORT against the frozen
ORACLE and never reads `checks/e2e.sh`, so under both plants its only disagreement was the port's own
refusal, its stdout empty. Both pins moved with the edit and `revert(oracle) == e2e.sh` is still
proved byte for byte. Evidence: `.agents/slop/e2esh/FINDINGS.md` §1-5, and `VERDICTS.tsv`'s `e2e.sh`
row, which is a **pre-fix** measurement — the census is `rootcheck.sh`'s to re-run.