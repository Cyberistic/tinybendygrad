# `e2e.sh` → `checks/e2e.py` — the port, and what it reproduces

**NOT A COMMIT.** The coordinator verifies and commits.

## What is on disk

| path | what it is |
|---|---|
| `checks/e2e.py` | the port. `--help` states what it gates and each verdict's DENOMINATOR |
| `.agents/slop/e2e.sh` | the shim — the path the gate's own header advertises, kept working |
| `.agents/slop/e2epy/oracle-e2e.sh` | the frozen shell body, still RUNNABLE |
| `.agents/slop/e2epy/diff.py` | the per-stage diff driver (oracle vs port, per input class) |
| `.agents/slop/e2epy/fixtures/` | the plant trees, built by the driver |
| `.agents/slop/e2epy/artifacts/` | both sides' stdout/stderr/exit, kept — a gate is a text |

## The pins, checked IN CODE on every run

Three assertions, all from the one file that survives:

1. the frozen oracle's own sha256 == `ORACLE_SHA`;
2. **the oracle with its ONE documented edit reversed** == `BODY_SHA`, the shell body this port
   was diffed against — so the edit is provably still the only difference;
3. `checks/e2e.sh`, **if it is still on disk**, == `BODY_SHA`.

The oracle's only edit is `ROOT=${E2E_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}`, so a copy two
directories deeper than the repository root can be run at all. It is not cosmetic — see FINDING 1.

Drift refuses with **exit 3** and says which of the three failed.
## FINDING 1 — `checks/e2e.sh:30` silently runs in the WRONG TREE from the wrong depth

```sh
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
```

`checks/e2e.sh` and `.agents/slop/e2e.sh` are both **two** levels deep, so `../..` is the
repository and both work. The frozen oracle at `.agents/slop/e2epy/oracle-e2e.sh` is **three**, and
`../..` is then `.agents/` — **which EXISTS**, so `cd "$ROOT"` SUCCEEDS and the script proceeds
happily in a directory that is not the repository. Measured:

```
$ env -i PATH=/tmp/emptydir /bin/sh -c 'echo $PATH'
/tmp/emptydir
$ env -i PATH=/tmp/emptydir /bin/zsh -c 'echo $PATH'
/Users/cyberistic/.nub/node-shim:/Users/cyberistic/.cargo/bin:/tmp/emptydir
```

The first line is why the oracle's ONE documented edit (`E2E_ROOT`) is **mandatory and not
cosmetic**: without it the oracle cannot be run from `e2epy/` at all, which is also why
`checks/substrate.py` and `checks/differ.py` each carry the same one-line override. There is no
`[ -d "$ROOT/checks" ]` sanity check anywhere in the shell.

## FINDING 2 — the shell runs NO stage subprocess concurrently, and neither does any of the four it delegates to

Asked directly, because a port that *could* run two `bend` processes would summon the crash.

Measured over `checks/e2e.sh` **and** all four stage scripts it invokes
(`opsbend-milestone.sh`, `e2e_port/run-port-mm.sh`, `f64/run-f64.sh`, `jstage/jsstage.py`), plus
`e2e_mm.py`, `e2e_mm_run.mjs`, `e2e_mm_gate.py`:

| construct | hits |
|---|---|
| background `&` | **0** |
| `wait` | **0** (the 3 in `e2e_mm.py` are the word `wait` in prose and `Cs.wait` calls) |
| `$!` | **0** |
| `xargs … -P` | **0** |
| `subprocess.Popen` / `fork` / threads / `Promise.all` | **0** (`jsstage.py` uses blocking `subprocess.run` ×4) |

Every spawn in every stage script is a **foreground blocking call** (`opsbend-milestone.sh:51,61,68,79`,
`run-port-mm.sh:124,136,156,…`, `run-f64.sh:120,149,208,…`). **THE ORDERING IS REAL AND THE PORT
KEEPS IT:** `stage()` is the only place a process is started in `checks/e2e.py` and it blocks, so no
two stages and no two children of one stage can be live at once.

**WHAT THE SHELL HAS NO CONCERN ABOUT — REPORTED, NOT FIXED.** `ulimit` appears **zero** times in
`e2e.sh`, and none of its four stage scripts bounds memory either. The port deliberately does **not**
add `checks/bounded.py`: a kill is reported as exit **3** and a timeout as exit **4**, and **stage 7
READS 3 AS A VERDICT** (`run-f64.sh` refusing on a cold substrate is `SKIP`, and that refusal is the
shell's own third outcome). A bound that changes an exit status changes a verdict line, so adding one
silently is exactly the failure the migration rule forbids. The gap is this paragraph.

## FINDING 3 — arguments: THE SHELL READS NONE, and neither does the port except `--help`

`checks/e2e.sh` has **no `getopts`, no `shift`, no `$@`, no `$*`, and one `$0`** (the `dirname` above).
The `$1`/`$2` at lines 78–82 are the shell function `verdict`'s own parameters. So
`sh checks/e2e.sh --help --nonsense -x` runs all eight stages and ignores every word.

`checks/e2e.py` matches: it inspects only `sys.argv[1]` for `-h`/`--help`, and **every other argument
is ignored**, because failing on an argument the shell ignored would be a verdict change.
`--help` is the one deliberate addition — it prints the gates and their denominators and exits 0,
and it is not a verdict. There is no zero-argument refusal here to port, because the shell has none:
this gate takes no input at all.

## FINDING 4 — the live cleanup unit TRUNCATED `checks/e2e.sh` to 0 bytes, mid-port

`jj log` shows a live unit `qmyqvmnpsloz`: *"cleanup: **THE POLICY IS "PYTHON ONLY", AND THE
MEASUREMENT IS **103 ONE-OFF `.sh` DELETED**"*. Measured, in this order:

1. `checks/e2e.sh` was read in full at 15:0x, copied byte-identically to
   `.agents/slop/e2epy/oracle-e2e.sh`, and the copy verified against it (`diff` reported no
   difference).
2. Minutes later `checks/e2e.sh` hashed to `e3b0c44298fc1c14…` — **the sha256 of the EMPTY STRING**.
   Not deleted: **truncated to zero bytes**, and still executable.
3. `checks/e2e.py` refused to run at all: its own pin said `checks/e2e.sh: MISSING`.

**A 0-BYTE `#!/bin/sh` RUNS AND EXITS 0 PRINTING NOTHING.** So `sh checks/e2e.sh` would have been a
green exit with no artifact — this project's oldest failure (`bend --check-only` answers
`ALL PROOFS CHECK` for an empty file) landing on **the one artifact**, and a reader would see nothing
at all rather than a wrong number. It was restored byte-exactly from the frozen oracle
(20,301 bytes, sha256 `f222c02c…`, verified before writing).

**THE ORACLE IS WHAT MADE THAT RECOVERABLE.** Had the port not frozen the shell body first, the
comparison this whole migration rests on would have had nothing to compare against, and the only
surviving copy would have been an empty file. That is the migration rule paying for itself.

Not mine to fix and not fixed here: whether the cleanup unit should truncate rather than delete, and
whether `checks/e2e.py` should be re-pointed at the now-single Python entry point. Both are the
coordinator's.

## FINDING 5 — the port's own bugs, all three found by plants rather than by reading

Every one of these was invisible to the `live` set and would have shipped.

| # | plant | symptom | fix |
|---|---|---|---|
| 1 | `plant-no-zsh` | `FileNotFoundError` traceback out of stage 6. Stages 7 and 8 **never ran**, no summary printed, and the gate exited 1 **by crashing**, not by deciding — while stage 7 has a whole `rc -eq 127` SKIP branch that was unreachable. | `stage()` returns **127** for a missing command and **126** for a non-executable one, writing the shell's own words to the stream the stage captures into |
| 2 | `plant-thin`, `plant-deadbend` | `echo ... >&2` lines written without their newline: **9 stderr lines diffed against 1**. Exit status and stdout were already correct. | `say_err` takes bytes and the callers pass the `\n`; `head -3` output is passed unmodified so a file whose last line has no newline does not gain one |
| 3 | every set | readers went through `read_text(errors="replace")`, which substitutes U+FFFD. `cat`/`tail`/`grep` are byte-transparent, so a stage emitting one non-UTF-8 byte would have produced a different artifact while every visible character matched. | the whole read/print path is bytes: `raw()` → `bytes`, and the two filters are `bytes` patterns |

## FINDING 6 — `zsh` REWRITES `PATH`, and an earlier cut of my own driver ran the oracle under it

```
$ env -i PATH=/tmp/emptydir /bin/sh   -c 'echo $PATH'   ->  /tmp/emptydir
$ env -i PATH=/tmp/emptydir /bin/zsh -c 'echo $PATH'   ->  /Users/cyberistic/.nub/node-shim:/Users/cyberistic/.cargo/bin:/tmp/emptydir
```

The oracle's shebang is `#!/bin/sh`. The driver invoked it with `zsh`, so `plant-no-node` reported
`stage 3 gpu (node): FAIL (rc=1)` — zsh had put the node shim back on `PATH` before the script's
first line — while the port, run under python, correctly said `SKIP`. **The driver was disagreeing
with itself, not the port.** Fixed by invoking `sh` by absolute path, which is also what lets
`plant-no-zsh` withhold zsh while the driver keeps an interpreter.

Worth recording separately: `checks/substrate/diff.py` and `checks/differ.py` both invoke their
oracle with `zsh`, and both oracles are `#!/bin/zsh` — so they are consistent and this finding does
**not** apply to them. It applies to any driver that runs a `#!/bin/sh` oracle under zsh.

## FINDING 7 — how a refusal is told apart from a failure, and why the port does NOT add a memory bound

The three outcomes are the shell's and they are load-bearing:

| outcome | meaning | exit | reaches the gate's exit status? |
|---|---|---|---|
| `PASS` | ran and agreed | 0 | — |
| `FAIL (rc=N)` | **ran** and disagreed | N | **yes** |
| `SKIP -- …` | **could not run**; measured nothing | — | **no** |

`SKIP IS NOT PASS` and `FAIL IS NOT RETRACTED`: the summary says *"a failing stage does not retract
the others' claims"* and still exits 1, and it says `PASS-WITH-SKIP IS NOT PASS` and still exits 0.
Both halves are deliberate and the port reproduces both (`checks/e2e.py:381-401`).

**THE ASYMMETRY IN STAGE 7 IS THE SHELL'S, KEPT.** No `zsh` is stage 6's `FAIL (rc=127)` **and**
stage 7's `SKIP` in the same run. One missing tool, two different verdicts, because stage 6 has no
`127` branch and stage 7 does (`checks/e2e.sh:227-235`). `plant-no-zsh` compares this exactly:

```
== 6/6 the matmul THROUGH THE PORT …
  stage 6 port (matmul THROUGH the port, no Node): FAIL (rc=127)
== 7/7 the SAME kernel in f64 THROUGH THE PORT …
  stage 7 f64 (double through the port, no Node): SKIP -- `zsh` is not available; stage 7 measured NOTHING
```

**WHY NO MEMORY BOUND.** Routing a stage through `checks/bounded.py` reports a kill as exit **3** and
a timeout as exit **4**. Stage 7 **reads 3 as a verdict** — `run-f64.sh` refusing on a cold substrate
is `SKIP`, not failure — so a bound cannot be added to stage 7 without making a refusal
indistinguishable from a kill. Stage 8 also reads 3 as `REFUSED`. Adding the bound would therefore
change verdict lines, which is the one direction this migration may not move. The gap is real and it
is named here rather than closed.

**THE STRUCTURAL ANSWER IS THE ORDERING, AND IT IS ALREADY THE SHELL'S.** `stage()` is the only
function in `checks/e2e.py` that starts a process and it blocks, so the two-`bend` crash condition
cannot be reached by writing to this file. What remains unbounded is a SINGLE `bend`, and the census
measured that population's median peak at 207 MB (`PEAKRSS.md`).

## FINDING 8 — `checks/e2e.sh:30` BROKE THE `live` DIFF RUN, and it is FINDING 1 again

The first `live` comparison ran the oracle with no `E2E_ROOT`, so the oracle computed
`ROOT=<repo>/.agents` — **which exists** — and the gate proceeded there:

```
oracle: == 1/4 oracle (CPython tinygrad, DEV=CPU)
        …/.agents/.venv/bin/python: No such file or directory      exit 1, ONE line
port:   all eight stages, 15,705 bytes                            exit 1
```

`checks/e2e.py` was unaffected because it resolves `ROOT` from its own `__file__`. **A 0-byte-or-
wrong-directory gate that prints one line and exits non-zero looks exactly like a gate that
refused**, and on this tree the substrate was fine. The driver now sets `E2E_ROOT` for `live` too.

**THE SHALLOWER POINT, AND IT IS THE ONE TO CARRY:** `checks/e2e.sh` and `.agents/slop/e2e.sh` are
both two levels deep and work by accident of their own placement. Any *third* invocation path — a
symlink farm, a copy, a `gates/` wrapper, a `find`-discovered path — silently runs the gate in the
wrong tree and exits 1 with almost no output. `checks/e2e.py` has no such dependency: `ROOT` comes
from `__file__`, which is correct at any depth. **That is a robustness the port gains for free, and
it is worth recording as a difference rather than claiming it as a fix.**

## THE LIVE RUN — oracle and port, byte-identical, and WHAT THE VERDICT ACTUALLY IS

`.venv/bin/python .agents/slop/e2epy/diff.py --sets live` — the real repository, real `bend`, real
`node` + headless Chrome, real `cc`, both sides run **sequentially** (oracle first, then the port).

```
## live   exit: oracle=1  port=1
  stage 3 gpu (node)                            oracle=PASS   port=PASS
  stage 4 gate (matmul vs CPython, via WebGPU)  oracle=PASS   port=PASS
  stage 5 ops_bend (kernel executes in Bend)    oracle=PASS   port=PASS
  stage 6 port (matmul THROUGH the port, no Node) oracle=PASS  port=PASS
  stage 7 f64 (double through the port, no Node) oracle=PASS  port=PASS
  stage 8 js lane (node on runtime/dtype.js, 20 rows vs CPython) oracle=FAIL (rc=1)  port=FAIL (rc=1)
  block  0 IDENTICAL  == 1/4 oracle (CPython tinygrad, DEV=CPU)
  … 20 blocks, ALL IDENTICAL …
  stdout: IDENTICAL (15705 vs 15705 bytes)
  stderr: IDENTICAL (0 vs 0 bytes)
```

**sha256 of the two artifacts is the SAME FILE:**
`1f9744cbebaecd99ce624dd214c02b955a726561c2c0089c493996d734123fd6`, 15,705 bytes, 257 lines, on both
sides. Exit status 1 on both. **All 20 stage blocks identical — reported per block, not as one
aggregate pass**, because one "IDENTICAL" over eight stages would hide the one that differs.

### THE VERDICT I WAS ASKED TO REPRODUCE — and one honest difference

The brief's reference run was on an earlier HEAD: *stages 1–4 PASS · 5 PASS · **6 FAIL rc=1** · 7 PASS
· **8 FAIL rc=1** · 2 failed, 0 skipped · exit 1.*

**On the tree as it stands, stage 6 is PASS.** Its own output says why, in its own words:

```
PASS [64] 64 u32 words bit-identical to CPython, through the port's own runtime
THE 64/64, RECOMPUTED WITH diff AND NOT READ OUT OF THE LANE:  diff bytes = 0
STAGE 6 PASS -- 64/64 u32 words through the port's own renderer, diff 0 bytes
```

So the live run is **1 failed, 0 skipped, exit 1**, where the brief's reference was **2 failed**. The
difference is **not** in my port: the oracle produced the identical artifact. It is the substrate
having moved under the gate since the reference run — stage 6 was fixed by whoever owns it, in
exactly the way the brief said the two red stages "are not yours to fix". **I did not fix stage 6 and
the port reproduces whatever it says.** Stage 8 remains red on both sides, for the reason the brief
records: `rows that REACH dtype.js` = **0**, `pure dtype.bend` = **20**, and `CIDs dtype.js registers
that dtype.bend no longer calls` = **10**.

### WHAT I DID NOT TOUCH

Stage 6 and stage 8 are **RED-AND-NOT-MINE and were not fixed, re-pointed, retired or retuned.** The
brief's measured answer for stage 8 — *the true denominator IS 0 and the stage should be RETIRED, not
re-pointed* — is recorded in the port's `--help` and here, and left as the owning unit's call.

## FINDING 3b — `--help` is the ONE place the port and the shell DIFFER, and it is declared

Measured on `plant-pass`, four invocations each side:

| argv | oracle | port |
|---|---|---|
| *(none)* | exit 1, 28 lines | exit 1, 28 lines — **byte-identical** |
| `-x` | exit 1, 28 lines | exit 1, 28 lines — **byte-identical**, same sha `005c67a5…` |
| `foo bar baz` | exit 1, 28 lines | exit 1, 28 lines — **byte-identical**, same sha |
| `--help` | exit 1, **runs all eight stages** | **exit 0, 88 lines of `--help`** |

So `--help` is the single deliberate divergence, and it is not a verdict: the shell has no help and
no refusal. It is stated in `checks/e2e.py`'s docstring, in the shim's header, and here. Everything
else — junk flags, bare words, no arguments at all — is byte-identical, because the shell reads no
arguments and neither does the port.

## PLANT AND DISARM — 9 input classes, all byte-identical, 0 disagreements

`.venv/bin/python .agents/slop/e2epy/diff.py --sets <nine plants>` → **`0 of 9 disagree`**, every
plant `stdout: IDENTICAL`, `stderr: IDENTICAL`, exit status equal.

| plant | what it moves | reaches | exit | both sides |
|---|---|---|---|---|
| `plant-pass` | nothing fails | 8 stages | 1 | identical |
| `plant-passskip` | stage 7 refuses (rc 3) | 7 stages + 1 SKIP | 1 | identical |
| `plant-refuse` | stages 5, 6 fail; 7 refuses | all 8 | 1 | identical |
| `plant-stage8red` | stage 8 exits 1 | all 8 | 1 | identical |
| `plant-no-node` | **`node` off `PATH`** | stage 3 → SKIP | **4** | identical |
| `plant-no-zsh` | **`zsh` off `PATH`** | stage 6 FAIL 127, **stage 7 SKIP** | 1 | identical |
| `plant-thin` | `bend` emits 5 rows | **stage 2 aborts, exit 2** | 2 | identical |
| `plant-deadbend` | `bend` emits 0 rows, exit 0 | **stage 2 aborts, exit 2** | 2 | identical |
| `plant-stage1red` | stage 1 exits 3 | **stage 1 aborts, exit 3** | 3 | identical |

**Exit statuses 0, 1, 2, 3 AND 4 are all reached and all agree**, which is the part a single run
cannot show. **`plant-thin` and `plant-deadbend` are the ones that matter most**: they are the
eight-attempt retry path, `bend` printing nothing while exiting 0 — the exact failure `bend_run`
exists for — and both sides abort at **status 2 with the `set -e` shape**, no verdict line, no
summary.

`plant-no-node` says `PASS WITH 1 SKIP(S)` and now exits **4**. That shape is the one worth having
compared, and it was found by this very driver: on 2026-10-06 the summary printed
`SKIP IS NOT PASS` and the exit status was **0** anyway — three states in the exit status as two
numbers, so a caller reading only `$?` was told the port passed on a run where the f64 lane had
measured nothing. **A gate that exits 0 having done nothing is worse than no gate, because it is
trusted.** Both sides now exit 4 (`plant-no-node` is the only plant whose PATH is short enough to
reach the summary with no failure), the pin moved with the body in the same commit, and the
repro is `.agents/slop/skipexit/repro.py` — green, plus a FAIL column and a SKIP column, against
both the current gate and a frozen pre-fix copy, so it discriminates both ways. Measurement and the
two rejected options: `FINDINGS.md` §2.

## WHAT I COULD NOT PORT, WITH `file:line` — nothing, and here is the audit

Every stage command was carried across one for one. There is no stage whose behaviour I approximated:

| shell | port | carried |
|---|---|---|
| `checks/e2e.sh:29` `set -e` | the two `if rc := …: return rc` after stages 1 and 2 | the abort shape, the status, and the absence of a verdict line |
| `:30` `ROOT=$(cd "$(dirname "$0")/../..)` | `Path(__file__).resolve().parents[1]` | **+ robust at any depth** (FINDING 8) |
| `:34` `mkdir -p "$RUN"` | `RUN.mkdir(parents=True, exist_ok=True)` | |
| `:39-56` `bend_run` | `bend_run` | 8 attempts, `> 20` rows, `sleep 1`, the **empty-`rows`** first message, `head -3`, `return 2` |
| `:75-83` `FAILS`/`SKIPS`/`verdict`/`skip` | module globals + `verdict`/`skip` | three outcomes |
| `:96` `command -v node` | `which("node")` | |
| `:110` gate → file, `:113` `cat` | `stage(..., gate)` + `echo_file` | status from the command, never a pipeline |
| `:145,148` ops_bend → file, `tail -3` | `stage(..., ops)` + `tail_file` | |
| `:185,188` port mm → file, `cat` | `stage(..., pmm)` + `echo_file` | |
| `:222,232` f64 → file, `grep -E … \| sed` | `stage(..., f64)` + `grep_file(F64_RE)` | the **same filter**, incl. `RED   \[`'s three spaces |
| `:227-235` rc 3 / rc 127 / else | the same three-way | |
| `:309-313` temp + `rc=$?` + `mv` | `tmp.unlink` + `stage` + stamp + `os.replace` | same-directory, so still atomic |
| `:320-322` `grep -c '^rc='`, `sed … \| tail -1`, `:-1` | `stamps`, `RC_STAMP_RE`, `-1` | |
| `:323-324` js filter | `grep_file(JS_RE)` | |
| `:325-338` three-way on `jsrc`/`jsgate`/`jsstage_rc` | the same three-way | |
| `:346-359` summary + three exits | the same, byte for byte | |

**Two things the shell does that the port does NOT do, both deliberate and both reported above:**
`env -u PYTHONPATH` (the shell never applied it; applying it would change what `e2e_mm.py` can
import), and any memory or time bound (a kill reads as 3, which **stage 7 and stage 8 both interpret
as a verdict**).

**One thing the port does that the shell does not, and it is not a behaviour change:** the three-pin
oracle correspondence check, which can only turn a run that would otherwise have produced a verdict
into exit 3.

## HOUSE RULES HONOURED

- **Did NOT touch** `checks/{differ,substrate,sweep,bounded,no-strays,no-shrink}.py`, any `.bend`,
  `runtime/**`, `uop/**`, `renderer/**`, `helpers.bend`, `graphcmp*`, `reader-*`, `abi_gate.py`,
  `abi4/**`, `jsfix/**`, `clangshim/**`, `clangfill/**`, or another unit's tree. `checks/e2e.sh` was
  restored byte-exactly because the cleanup unit emptied it, not edited by me.
- **`.agents/slop/differverdict/root/` IS EXCLUDED AND SAID SO.** It is a full copy of the repository
  (253 MB, 9,301 files). **Nothing in this unit walks it** — no `find`, no glob over `.agents/slop`,
  and every path in `diff.py` is named explicitly. Every sweep I ran named its inputs.
- **No `bend` processes ran concurrently, ever.** `diff.py` starts each side with one blocking
  `subprocess.run` and runs the sides in order; `checks/e2e.py` has exactly one function that starts
  a process and it blocks. All 9 plants use a **stub** `bend` and run no real compiler.
- **Never committed.**
- **`substrate-check.sh`** is being ported by another unit; I did not read its verdict, depend on it,
  or move. Nothing in this port touches it.

## FOR THE COORDINATOR — three decisions, not mine

1. **`AGENTS.md` now says new gate code goes in `gates/*.py` and `.agents/slop/` is being pruned.**
   My brief assigned `.agents/slop/e2epy/`, and `agent-core.md` says oracles live in `.agents/slop/`.
   I followed my brief. If the new rule wins, the **diff driver** should move to `gates/`; the
   **oracle must not**, or the "oracles live beside the code they check" rule breaks.
2. **`checks/e2e.sh` is now redundant** — `.agents/slop/e2e.sh` and `checks/e2e.py` both work. The
   cleanup unit is deleting one-off `.sh`; whether `checks/e2e.sh` becomes a third shim or is retired
   is a call about which paths the project wants to keep, and the frozen oracle is what makes it safe
   either way.
3. **Stage 6's flip from FAIL to PASS was not mine and is not in any commit of mine.** If the
   coordinator wants the brief's `2 failed` reference rather than the tree's current `1 failed`, that
   difference is the substrate, and both sides of my diff report it identically.

## THE SHIM IS CHECKED TOO, NOT JUST ASSUMED

`.agents/slop/e2e.sh` run on `plant-passskip`, against `checks/e2e.py` invoked directly:

```
SHIM   exit=1
DIRECT exit=1
shim output == direct output:  IDENTICAL  (sha a3368af961ef2aaa)
```

**ONE THING THE SHIM NEEDS AND THE SHELL DID NOT: `dirname`.** The shim's `cd "$(dirname "$0")/../.."`
is the substrate unit's idiom, and with a PATH that has no `dirname` in it the shim printed
`line 16: dirname: command not found`, then `cd ""` failed, and it **`exec`'d
`/.venv/bin/python` and exited 0** — three failures, one green status. Measured, not hypothetical:

```
.agents/slop/e2e.sh: line 16: dirname: command not found
.agents/slop/e2e.sh: line 17: /.venv/bin/python: No such file or directory
.agents/slop/e2e.sh: line 17: exec: /.venv/bin/python: cannot execute: No such file or directory
shim exit=0
```

`exit 0` from a shim that ran nothing is the **third** instance this session of a gate exiting 0
having measured nothing — the same defect as the 0-byte `checks/e2e.sh`, arriving by a different
route. `checks/substrate-check.sh` has the same two lines and the same exposure.

**NOT FIXED IN MY FILES, and reported instead:** the shim is not on my list of files to harden
beyond making it work, `checks/substrate-check.sh` is another unit's, and "replace `dirname` with
`${0%/*}`" is a change to a shim another unit may be rewriting. **It is a one-line fix in four
shims and it is worth doing.** Recorded in the TODO handoff below.

## NOTE ON THE PIN-RESOLUTION PATH I CHANGED MID-RUN

The drift check originally resolved both pins against `ROOT`. That is wrong the moment `E2E_ROOT`
points the eight stages at a fixture tree: the port then looked for the oracle *inside the fixture*,
reported `MISSING`, and **refused to compare anything** — which is what the first `plant-pass` run
did. Pins belong to the tree that ships the code, so they resolve against `REPO` (`__file__`), not
`ROOT` (the tree under test). Recorded because "the gate refused to run" is the failure mode that
looks most like correctness.
