# SUBSTRATE — the port of `substrate-check.sh` to Python, and what it agrees on

**Nothing committed.** The coordinator verifies and commits. Unit `.agents/slop/substrate/`.
Owns `checks/substrate.py`, `.agents/slop/substrate-check.sh`, `checks/substrate-check.sh`, and
this directory. **No file inside `tinybendygrad/` was created or touched.**

Compiler **Bend 2.0.34**. Measured 2026-10-05 ~15:10, on a tree five units were editing
concurrently. `tinybendygrad/` held **153 files, 138 of them `.bend`**.

## 1. THE FILES, AND WHAT EACH ONE CLAIMS

| file | what it is |
|---|---|
| `checks/substrate.py` | the port. `--help` states what it gates and each verdict's denominator |
| `checks/substrate-check.sh` | `exec` shim (was the 470-line body) |
| `.agents/slop/substrate-check.sh` | `exec` shim (was the 470-line body) |
| `.agents/slop/substrate/oracle-check.sh` | the **frozen oracle**, still `+x`, still runnable. sha256 `6d1000712f0f…600e`, pinned in CODE in `checks/substrate.py` `ORACLE_PIN` and refused with exit 3 on drift |
| `.agents/slop/substrate/diff.py` | the diff harness: 6 input sets, 4 plants, disarms all of them |
| `.agents/slop/substrate/fixtures/` | the 4 fixture files the input classes are made of |
| `.agents/slop/substrate/artifacts/<set>/` | per set: `oracle.{out,err,rc}`, `python.{out,err,rc}`, `{oracle,python}.norm`, `diff.txt` |

**`.agents/slop/differverdict/root/` IS A FULL COPY OF THE REPOSITORY** made by a live unit —
75 `.sh` under its own `.agents/slop/` alone. It is **EXCLUDED**: `diff.py` names its inputs
explicitly and never walks a tree, and `tinybendygrad/**` is enumerated with `rglob` under that
one directory. No `find` in this unit touches it.

## 2. THE VERDICT, AND IT IS THE SAME VERDICT

> **The port reproduces the shell's verdict, denominators, exit status, and whole output stream,
> byte for byte, on every input class — and it changed no verdict.**

Six sets, all `stdout=IDENTICAL`, all exit statuses equal:

| set | what it is | exit (both) | lines |
|---|---|---|---|
| `smoke` | every route, one file each: WARM `.bend`, COLD `.bend`, EMPTY, NO INSTRUMENT, MISSING, `.c`, `.js` | 1 | 24 |
| `names` | `-n`: HALF 2 only, including a `NO INSTRUMENT` file that `-n` does **not** skip | 0 | 23 |
| `newline` | ONE argument containing an embedded newline | 1 | 14 |
| `refused` | **zero arguments** | **3** | 4 |
| `route` | all four routes over real tree files, incl. `sz.bend` and `renderer/nir.bend` | 1 | 35 |
| `pop` | **every file under `tinybendygrad/`** — 153 arguments | 1 | see `artifacts/pop/diff.txt` |

The comparison is byte identity of **stdout** plus **exit-status equality**, and it asserts the
**SHAPE** of both sides (no 0-byte stream, a verdict line present) — because `cmp` on two empty
files succeeds, and that is how a killed run looks identical to a clean one.

**ONE normalisation: the program's own name.** The refusal's usage line prints `$0`, as the shell
did. `zsh <oracle path>` and `checks/substrate.py` cannot agree on that token, so it is replaced
by `<SELF>` on both sides and **nothing else is touched**. **stderr is not compared** — the port
reports kills there, which the shell could not do, and folding that in would fail every run for a
difference the port was *asked* to make.

## 3. THE ZERO-ARGUMENT REFUSAL, TESTED

```
$ .venv/bin/python checks/substrate.py ; echo rc=$?
REFUSED: no files given. A guard invoked with an empty population must not
report agreement -- that is indistinguishable from a green run over nothing.
usage: checks/substrate.py <file.bend|file.c|file.js> [more ...]
       or: find tinybendygrad -name '*.bend' | xargs checks/substrate.py
rc=3
```
Identical through the `.sh` shim, and the `refused` set diffs it against the oracle: **exit 3
both, stdout byte-identical, 4 lines.** A refusal checked only by hand is a refusal nobody
checked.

## 4. THE MEMORY BOUND, WHERE THE SHELL HAD ONLY AN ALARM

**THIS IS THE ONE PLACE THE PORT IS STRICTLY BETTER, AND IT IS THE POINT.**

| site | shell | port |
|---|---|---|
| `bend --check-only` | `perl -e 'alarm 300; exec @ARGV'` — **time only** | `checks/bounded.py --mb 2048 --seconds 300` |
| `node --check` | same alarm | same bound |
| `cc -fsyntax-only` (context, and fragment) | **NO TIME BOUND AT ALL** | same bound |
| `bend -o` for the C context | `alarm 300` | same bound |

`ulimit` appears zero times in `agent-core.md`, `substrate-check.sh` and `e2e.sh` combined, and
two unbounded `bend` processes took this machine's memory to zero on 2026-10-05. Every
invocation here is sequential — **never two `bend` processes at once.**

**WHY 2048 MB AND NOT THE CENSUS'S 1024.** `runs/peakrss.json` measured a max of **1,152 MB**
(`renderer/nir.bend`) and 1,108 MB (`sz.bend`), **both killed at the 1 GB ceiling.** Re-measured
today through this port: **`sz.bend` peaked at 1,468 MB and `renderer/nir.bend` at 1,435 MB.** A
ceiling below the population's own maximum is a ceiling that **changes verdicts**, and a port that
changes a verdict has not ported. 2048 MB is above every measurement, and it is the plant that
proves the point (§6).

**Kills and timeouts go to STDERR, never into the verdict line.** A killed child produced no
output under the shell's alarm either, so the verdict line is the shell's byte for byte and the
fact that it was KILLED is reported on its own channel:
```
[substrate] tinybendygrad/sz.bend: [bounded] WITHIN-LIMITS  rc=1  peak-RSS=1468 MB (ceiling 2048)  3s
```
**A gate is a text: a line added to the artifact is a line the oracle does not have.**

## 5. TWO BUGS THE DIFF CAUGHT IN THE PORT, BOTH FROM THE NEW TEST SETS

Both were found by a set added *because* the class was untested — not by reading the code.

1. **`"tinybendygrad/"` where the shell has `"tinygrad/"`** (PROVENANCE). The upstream `.py` lives
   in the **other** tree. Every live `.bend` read `no-upstream`, `port=` fell to 0, and the PORT
   ALARM was the only line still true. Caught by the `newline` set.
2. **THE STRING-LITERAL REGEX, "fixed" into being wrong.** The shell's `python3 -c` body is inside
   a **shell single-quoted string**, so the four backslashes in
   `re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"", …)` are passed through as four and reach Python's raw string
   as four, which the engine reads as **two** escaped backslashes — so it matches a run of TWO
   literal backslashes where `[^"\\]` excludes ONE. The port wrote the *obvious* regex and
   disagreed by **exactly one `unseen`** on `uop/validate.bend`, 547 vs 548, on a 663-reference
   line: one mis-stripped literal turned a quoted name into a `Foo.bar` reference.
   **The oracle is right by accident and the port was wrong on purpose. Nothing to fix — only to
   reproduce**, and the comment at `checks/substrate.py` `STRING` is the only thing standing
   between the next reader and a well-meaning repair that breaks the gate.

## 6. PLANTS AND DISARM — FOUR, ALL FIRED, ALL DISARMED

| plant | what it must do | result |
|---|---|---|
| `--mb 1` on `sz.bend` | port DISAGREE, oracle (no bound) says `:: SOME PROOFS FAIL` and the port says `:: ` — **the ceiling must not be able to change a verdict** | **DISAGREE, as demanded** |
| one trailing space in the `ALL PROOFS CHECK` literal, in a copy of the port | `WARM` → `COLD`, and the port's own line reads `:: ALL PROOFS CHECK` — a COLD naming the verdict it failed to match | **DISAGREE, as demanded**, exit 0→1 |
| `fixtures/broken.bend` made valid | the set's output must MOVE (it is the only COLD row) | **moved, as demanded** |
| `fixtures/empty.bend` made non-empty | the set's output must MOVE (this is the trap the gate exists for) | **moved, as demanded** |
| all four disarmed | the real port, same inputs | **AGREE, byte-identical** |

**Two harness bugs the plants found in the harness, which is the point:**

- The `--mb` plant was passed to **both** drivers at first, so the oracle answered
  `MISSING --mb` / `MISSING 1` and the diff passed **for the wrong reason** — it was comparing
  two different arguments. `extra` (both sides) and `port_extra` (port only) are now separate.
  (It did buy a control for free: the oracle treats an unknown `-x` as a **FILENAME**, which is
  the rule `split_leading` reproduces.)
- The `--mb 1` plant used **`device.bend`, which peaks at 0 MB** — so no ceiling above zero could
  ever kill it and the two sides AGREED. A plant that cannot fail proves nothing. It is now
  `sz.bend`, and the reason is printed.

**One thing the plant polarity got wrong, kept because the confusion is worth recording:** a
plant's success is a **disagreement**, so its `True` cannot be folded into the sets' `ok`. The
first version did exactly that and printed `VERDICT: DISAGREEMENT` on a run where every plant had
just done its job. `demanded(ok, expected, name)` now prints the expectation for every run.

## 7. THE `--causes` ADDITION — FILES vs CAUSES, AND WHY IT IS OFF BY DEFAULT

`COLDNESS.md` §5: **35 red files, 15 causes**, one missing def (`O.ParamArg.no_slot`) reddens
**19**, and **41 of the 46 `BAD` sites are in `validate.bend`, which nothing imports.** The unit
of work is a **cause**.

`--causes` groups the COLD files by the error shape `--check-only` actually printed — `HOLOS`,
`FOREIGN`, `MISSING-DEF`, `DUPLICATE`, `UNKNOWN-CTOR`, `SYNTAX`, `TYPE-MISMATCH`, in that order
so the generic type-mismatch shape cannot swallow `a defined name` — and looks each symbol's
owner up in the names the files **under test** declare, so `DECLARED NOWHERE` means exactly that.

**It is OFF BY DEFAULT because it changes the output stream**, and the migration rule is that the
Python reproduces the shell's verdict on **every input**. Every diff above was run without it. It
cannot change a verdict or an exit status.

**`COLD` IS A COUNT OF FILES AND THAT IS STATED, NOT CHANGED.** `COLD` is still exactly "the
first line of `bend --check-only` is not `ALL PROOFS CHECK`", still a **per-file string compare**
with the **exit status discarded** (`--check-only` exits 1 on 14 clean files), and still over the
**whole transitive closure**, so a COLD file is very often red because of something it merely
imports. **The semantics are the shell's, deliberately. Preserved first, then questioned** — and
this is the report's answer to that question: *a closure-level COLD count is the wrong number to
steer work by, and `--causes` exists so the file count can be read next to the cause count. It
does not replace the verdict.*

## 8. WHAT COULD NOT BE PORTED, AND WHERE

1. **THE `.c` ROUTE HAS NO INSTRUMENT ON THIS TREE, AND IT IS NOT THE PORT'S FAITH.**
   `.agents/slop/guardfix/probe-c.bend` — the one bend program that makes `cc` able to read a `.c`
   fragment at all — **does not exist.** `guardfix/` holds only `disarm.sh` and `RESULTS.md`.
   `c_context()` therefore returns 1 and both drivers print
   `NO INSTRUMENT  tinybendygrad/runtime/dtype.c  (322 lines)  :: cc and a compiling bend C
   context are both required, and one is absent`. `guardfix/RESULTS.md` records this route
   **working** (`dtype.c` 0 errors, `sz.c` 0 errors, a real syntax error still caught), so the
   capability is ported and **unreachable**: the port raises the same alarm in the same order and
   for the same reason. **Restore `probe-c.bend` and this route comes back with no code change.**
   Both `NO INSTRUMENT` wordings are reproduced, including the **asymmetry** that only the routed
   one carries `:: …` and not `:: … -- **NOT JUDGED, AND NOT COLD**` (`substrate.py` `half1`,
   the `cc` branch) — a missing context says only *why*, an unrouteable class says *that*.
2. **`substrate-check.sh`'s OWN LINE NUMBERS ARE IN THE ORACLE, NOT THE PORT.** The port's
   comments cite `oracle-check.sh` line positions (`cd` at 65, the `alarm` at 200, `tinygrad/` at
   317). The oracle copy differs from the committed body by exactly one documented edit — the
   `SUBSTRATE_REPO` default in its `cd` — so **every line number after 65 is shifted by the two
   comment lines that edit added.** Cite the committed body, not the copy.
3. **`c_context`'s `#endif`-BALANCING is reproduced by COUNT, as the shell does** (`o - c` closes
   appended), not by which `#if` opened them. It is not reimplemented, so it has the shell's
   blind spot rather than a new one.
4. **The shell embeds TWO `python3 -c` programs.** Both are ported into functions, and both keep
   their behaviour, but the shell runs them under the **system** `python3` while the port runs
   under `.venv/bin/python`. `open(…, errors="replace")` is the only encoding-sensitive call and
   the port pins `encoding="utf-8"` explicitly, so the two agree on ASCII and would agree on any
   UTF-8 tree; they would diverge only on a tree that is neither, which is not this one.

## 9. REPRODUCE

```sh
.venv/bin/python checks/substrate.py --help                 # what it gates, and each denominator
zsh .agents/slop/substrate-check.sh tinybendygrad/device.bend   # the shim, still working
SUBSTRATE_REPO=$PWD zsh .agents/slop/substrate/oracle-check.sh tinybendygrad/device.bend  # the oracle
.venv/bin/python .agents/slop/substrate/diff.py                       # 6 sets
.venv/bin/python .agents/slop/substrate/diff.py --plants --sets smoke names newline refused route
.venv/bin/python .agents/slop/substrate/diff.py --sets smoke names newline refused route pop   # the
                                                                                                # whole tree
```
`--plants` needs `smoke` in `--sets` (it is the fixture plants' baseline). Artifacts:
`.agents/slop/substrate/artifacts/<set>/diff.txt`.

**THE PIN IS IN CODE.** `ORACLE_PIN` in `checks/substrate.py` is checked on **every** run and
refuses with **exit 3** and `ORACLE DRIFT: <file>: <got> != pinned <want>`. `checks/differ.py`
wrote its pin into a comment first and it caught nothing; the pin was CORRECT and was still a
comment that added up. **Measured here too:** the `plant-literal` mutant lives at
`artifacts/mutant/substrate.py`, so `ROOT = parents[1]` is `artifacts/` and the pin resolves to
nothing — the mutant refused with `ORACLE DRIFT` on **every** input and printed **zero bytes**,
and a bare "did the two outputs differ" said the plant had fired while it had proved only that
the **pin works**. The plant now demands its **own signature** in the verdict lines.