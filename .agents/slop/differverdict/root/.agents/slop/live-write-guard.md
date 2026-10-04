# live-write-guard -- the 157th harness

Run 2026-10-04, 12:05.  `python3 .agents/slop/live-write-guard.py`; rc=1.
Full failure list: `.agents/slop/live-write-guard-report.txt`.

## THE RULE, WHICH IS MECHANICAL

    A harness may not NAME a write into `tinybendygrad/`, unless it is registered in
    `.agents/slop/live-write-registry.txt` with a reason and a date.

Not "write to a snapshot".  Not "take a digest first".  Both have been tried in this
corpus and both are skippable by a tired agent at 4am.  This one is checkable by
reading a single file, and adding yourself to the registry is a deliberate act with your
name on it, which is the only enforcement mechanism that has ever worked here.

`staged_mut.Staged` needs no registry entry: its only destination is the staged copy
beside the target, so the AST cannot name a live path at all.

## WHAT IT CHECKS, and each of the three has been the actual failure

| check | detector | what it catches |
|---|---|---|
| WRITES | `mutanchor.write_spellings` | any destination under `tinybendygrad/` |
| DEBRIS | filename markers + PID liveness | a `.mut`/`.bak`/`.staged-` leftover a killed run left |
| UNGUARDED SUBSTRATE | `mutanchor.targets` + `imports` | a harness that names a live `.bend` and does not import `staged_mut` |

The guard shares `mutanchor`'s detector rather than having its own, because a guard with
its own idea of `open(P,'w')` is a second opinion nobody maintains.

## THE RESULT: 31 PROBLEMS, AND THE REGISTRY IS EMPTY

```
live-write-guard: 609 harness(es) read, 0 registered
debris: 4 DEBRIS, 2 IN-FLIGHT (a live staged mirror, its owner is running)
GUARD FAILED: 31 problem(s).
```

**A CORRECTION, MEASURED TWELVE MINUTES LATER.**  The run above says `0 registered`
and 27 failing harnesses.  Two minutes after I wrote it the guard reported
**`20 registered` and 9 failing** -- with the registry file visibly unchanged and empty.
That was a bug in `registered()`, mine, and the worst kind: it took the first
whitespace-token of every non-`#` line of the registry, so the registry's own PROSE
registered twenty harnesses, among them the word `A`, the word `harness`, and the module
name `staged_mut.Staged`.  A guard that counts its author's documentation as compliance
still prints a number, and the number is what gets quoted onward.

Fixed and now gated: an entry must be a `.py` filename at column 0, two spaces, a
reason, and the file must exist in the corpus.  Seven registry fixtures in `--selftest`,
including "prose at column 0" and "a ghost filename", all of which the first version
would have accepted.  **27 failing and 0 registered is the true state.**

### 27 unregistered live-tree writers

| harness | destination | spelling |
|---|---|---|
| `ag-fix1..13.py`, `ag-mutate.py` (14 files) | `runtime/support/autogen.bend` | `open(...).write` |
| `fold-lift-mutate.py`, `fold2-mutate.py` | `uop/fold.bend` | `open(...).write` |
| `nv_gate.py`, `nv_reshape.py` | `runtime/support/nv/nvdev.bend` | `open(...).write` |
| `ip_prune.py`, `ip_table.py` | `runtime/support/am/ip.bend` | `open(...).write` |
| `ptx-s3-gen.py` | `renderer/ptx.bend` | `open(...).write` |
| `ptx-s3-mutate.py` | `renderer/_ptxs3mut.bend` | `open(...).write`, `os.remove` |
| `amdev_mutate.py` | `runtime/support/am/_amdev_mut.bend` | `open(...).write`, `os.remove` |
| `fixplus.py` | `codegen/late.bend` | `open(...).write` |
| `ga_mutate.py` | `renderer/amd/generate.bend` | `write_text` |
| `tc-build.py` | `codegen/transcendental_f32.bend` | `open(...).write` |
| `mm-mutate.py` | `uop/probe-mmcore.bend.mut` | `open(...).write` |

**`nv_gate.py` and `nv_reshape.py` write `nvdev.bend`, and a unit was live on that file
while this guard was being written.**  That is the same shape as the
`blob-intern-mutate.py` incident with the names changed, and it is why the guard is
worth more than another note in `bend2-constraints.md`.

`mm-mutate.py` writes a `.mut` BESIDE a live `.bend` -- the `memory-mutate.py` spelling,
caught only after `_path` learned `BinOp(Add)`.  That one fix took the census from 27 to
this 28th finding, because `open(SRC + '.mut', 'w')` was invisible to it.

### 4 debris, and the IN-FLIGHT distinction is load-bearing

| state | path | bytes | age |
|---|---|---|---|
| DEBRIS | `tinybendygrad/runtime/ops_bend.mut.bend` | 80,583 | 1.6 d |
| DEBRIS | `tinybendygrad/runtime/support/elf.bend.mut` | 255,934 | 0.9 d |
| DEBRIS | `tinybendygrad/runtime/support/nv/nvdev.staged-nv-85779` | 114,264 | killed |
| DEBRIS | `tinybendygrad/runtime/support/nv/nvdev.staged-nv1-8831` | 114,264 | killed |
| IN-FLIGHT | `tinybendygrad/runtime/support/nv/nvdev.staged-mmut-69554` | 114,264 | pid alive |
| IN-FLIGHT | `tinybendygrad/runtime/support/nv/nvdev.staged-nv-50051` | 114,264 | pid alive |

**`ops_bend.mut.bend` IS VISIBLE TO `find tinybendygrad -name '*.bend'`.**  That is the
single worst thing in this tree: a census that globs `.bend` counts it as a port, and
`bin/bend` would try to compile it.

The first version of the debris check reported all six, because it asked only "does this
name look like debris".  Six units are live on six `.bend` files right now and the
debris list GREW from two items to six with four staged copies seconds old: four units'
in-flight mirrors.  A check that fails on a running unit's staged mirror gets deleted.
`staged_mut` ends its copy's name with the PID on purpose, so the question has an
answer: `os.kill(pid, 0)`.  A copy whose PID is alive is `IN-FLIGHT` and does not fail;
a copy whose PID is gone is the remains of a kill.

**NOTHING WAS DELETED.**  Two of the four DEBRIS items are another unit's; `nvdev.bend`
is a live unit's file and its `.staged-*` siblings are not mine to remove.

## TWO BUGS IN THE GUARD ITSELF, BOTH MEASURED, BOTH KEPT

**A `.bend` SUFFIX IS NOT A MARKER.**  The first debris rule was
`name.endswith(('.bend', '.mut', ...))`, which fires on all 131 real source files in the
tree.  A debris rule that fires on the healthy tree is a rule nobody reads.  Markers are
what make a copy a copy, and there are two spellings: appended (`elf.bend.mut`) and
inserted (`ops_bend.mut.bend`).

**A REGISTRY LINE IS NOT A REGISTRY ENTRY.**  See the correction above: the first
`registered()` read the file's own prose and reported `20 registered`.  The general form,
and it is the same shape as the `--report FILE` bug this unit hit twice: **a filter that
does not know what it is filtering will read its author's prose as data.**

**THE SELFTEST FIXTURES MUST NAME THE LIVE PATH AND CREATE NOTHING.**  The first version
pointed them at a temp directory, so every fixture was `SCRATCH` and the guard reported
`no live write` for an in-place writer with a `finally` restore.  The guard that would
have shipped `blob-intern-mutate.py` unchanged.  `mutanchor` only ever parses, so naming
`tinybendygrad/uop/ops.bend` in a source string writes no byte anywhere -- which is what
makes this a routine gate rather than something that needs a quiet machine.

```
SELFTEST -- 7 fixtures the guard has never seen, 4 of which MUST fire
  [AS EXPECTED] in-place write + finally restore               FIRED via open(...).write
  [AS EXPECTED] shutil.copyfile snapshot over the live file    FIRED via shutil.copyfile
  [AS EXPECTED] shell redirection onto the live file           FIRED via shell redirect in run
  [AS EXPECTED] a `.mut` BESIDE the live file, deleted after   FIRED via open(...).write
  [AS EXPECTED] the staged guard: no live write at all         no live write
  [AS EXPECTED] a pure reader of the live file                 no live write
  [AS EXPECTED] a reader of a RECORD, which is not the live tree no live write
  7/7 selftest fixtures behaved as required

REGISTRY PARSER -- 7 fixtures; the file is restored in a finally
  [AS EXPECTED] a real entry: name, TWO spaces, a reason       read 1, expected 1
  [AS EXPECTED] ONE space is not an entry                      read 0, expected 0
  [AS EXPECTED] prose at column 0 is not an entry              read 0, expected 0
  [AS EXPECTED] a module name is not an entry                  read 0, expected 0
  [AS EXPECTED] a ghost filename is not an entry               read 0, expected 0
  [AS EXPECTED] an indented example block is not an entry      read 0, expected 0
  [AS EXPECTED] a comment is not an entry                      read 0, expected 0
  registry restored: 0 real entries
```

### THE DEBRIS LIST SHRANK WHILE I WAS WORKING, WHICH IS ALSO THE ANSWER

At 12:10 there were 4 DEBRIS and 2 IN-FLIGHT.  At 12:31 there are **2 DEBRIS and 0
IN-FLIGHT**: both `nvdev.staged-*` kills were cleaned by their owners' runs completing,
because `Staged.__exit__` unlinks.  The two survivors are the ones with no PID to check
-- `ops_bend.mut.bend` and `elf.bend.mut`, both from harnesses that predate the staged
guard.  **The kill-window debris is self-healing and the pre-guard debris is not**, so
the list that will still be here tomorrow is exactly the one that predates this work.

## HOW TO MAKE IT THE DEFAULT

`live-write-guard.py --selftest && live-write-guard.py` in the same place
`rebase-gate-selftest.py` runs.  It exits 1 today, on 27 other units' harnesses, and
that is the intended direction: the first run of a new guard is supposed to be red.
Whoever owns each harness either converts it to `staged_mut.Staged` or writes one
justified registry line, and the count goes down to zero one file at a time.