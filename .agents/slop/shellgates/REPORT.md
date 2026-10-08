# `shellgates` — an instrument ran 17 shell gates with a Python interpreter, and could not see it

`gates/gate-surface.py:311` built every plant's command as `[str(PY), str(gate), *argv]`, while
`gates/gate-surface.py:357` filtered the population with `if p.suffix != ".py": continue`. **Both
halves of that sentence are one defect seen from two sides, and the second half is the reason the
first was never observed.** The filter meant `reach()` was never called with a `.sh` gate: the
shell half was not measured wrong, it was **invisible**, and an instrument that cannot see a
population cannot be anything.

**This is the fifth way a shell gate has failed in this tree.** `gates/README.md` records four:
`&&` masking a diff under `set -e`; an `EXIT` trap returning `rm`'s status; `<( )` not parsing
under `sh`; `${=SUB}` never expanding and a hash guard comparing `""` to `""`. This one is in an
**instrument**, so everybody quoted its numbers and nobody was counting the gate.

---

## 0. HOW MY OWN MEASUREMENT WAS WRONG FIRST, WITH THE BEFORE-VALUE

Three times, all in `.agents/slop/shellgates/siblings.py`, and the last is the one that matters:

| before | after | what my instrument was doing wrong |
|---|---|---|
| **34 of 59** resolved site/target pairs reported `MISMATCH` | 12 of 41 | **Scored argv[0]'s NAME against the target's shebang.** `subprocess.run(["./bin/bend", drv])` is a **DIRECT** exec — the kernel reads `bin/bend`'s `#!/bin/sh` and runs `sh`. The site *agrees*. 8 `checks/differ.py`-shaped sites were false. |
| 12 of 41 | **0 of 24** | **Counted every non-flag argument as an entry point.** `[PY, "checks/bounded.py", "--mb", "2048", "--", "./bin/bend", drv]` names `checks/bounded.py` as the script and `./bin/bend` as an **argument to it**. |
| 0 of 24 | **0 of 24** | **Read a third-party CLI's arguments as a script.** `["jj", "file", "show", "-r", rev, ".agents/slop/rebase-gate.py"]` ends in a repo path that is **DATA** — the revision of a file. This invented the last two "mismatches". |

Before-value, stated once: **`siblings.py` reported 34 defects in this tree; 34 of 34 were its
own bugs.** The corrected census reports **0 of 575 call sites**, over a denominator stated below.

**And here is the limit I cannot close, said plainly.** The census that exists to find
`gates/gate-surface.py:311` **cannot see it.** `reach(gate, argv)` takes its target as a
*parameter*, bound at the call site from `gates-pop.discover()`'s output, so no constant folder
reaches it: `gates/gate-surface.py` contributes **0 resolved sites and 0 mismatches** to its own
census. *A static census cannot see a defect whose target is a variable.* The fix below is
therefore not a census result — it is a **self-report on every plant**, plus three plants that
falsify it.

---

## 1. THE DIVERGENCE — 17 of 17, by shebang

Population: `gates/gates-pop.py:discover()` loaded **by path**, filtered by reading each file's
own `#!` line. `17 entry point(s) of 133` ship a SHELL interpreter. **Not by suffix.**

**Arms.** `SHEBANG` = what the file's `#!` declares. `BASH` = the arm
`.agents/slop/exitsurvey/shellentry.py:65` measured with, kept as a **control**. `PY` =
`.venv/bin/python <gate>`, which is exactly what `gate-surface.py:311` builds.
**argv is `[]` for all 17, uniformly** — giving some gates their documented argument and others
none would be a hand list, and the arms would then differ by argv rather than by interpreter.

| gate | `#!` | SHEBANG arm | BASH arm | PY arm | flip |
|---|---|---|---|---|---|
| `checks/bounded-selftest.sh` | sh | **PASS** (0) | PASS (0) | FAIL (1) | YES |
| `checks/classify.sh` | zsh | FAIL (1) | FAIL (1) | FAIL (1) | no |
| `checks/demo.sh` | zsh | **PASS** (0) | PASS (0) | FAIL (1) | YES |
| `checks/disarm.sh` | zsh | **PASS** (0) | **COMMAND-NOT-FOUND (127)** | FAIL (1) | YES |
| `checks/e2e.sh` | sh | FAIL (1) *(420 s)* | FAIL (1) | FAIL (1) | no |
| `checks/gate.sh` | zsh | UNASSIGNED (2) | UNASSIGNED (2) | FAIL (1) | YES |
| `checks/gen.sh` | sh | **PASS** (0) | PASS (0) | FAIL (1) | YES |
| `checks/lint_demo.sh` | zsh | FAIL (1) | UNASSIGNED (2) | FAIL (1) | no |
| `checks/lintable-gate.sh` | sh | FAIL (1) | FAIL (1) | FAIL (1) | no |
| `checks/plant.sh` | zsh | FAIL (1) | FAIL (1) | FAIL (1) | no |
| `checks/run-all.sh` | zsh | UNASSIGNED (2) | UNASSIGNED (2) | FAIL (1) | YES |
| `checks/run-f64.sh` | zsh | **REFUSED** (3) | UNASSIGNED (2) | FAIL (1) | YES |
| `checks/run-port-mm.sh` | zsh | FAIL (1) *(420 s)* | UNASSIGNED (2) | FAIL (1) | no |
| `checks/sb-gate.sh` | sh | **REFUSED** (3) | REFUSED (3) | FAIL (1) | YES |
| `checks/substrate-check.sh` | sh | **REFUSED** (3) | REFUSED (3) | FAIL (1) | YES |
| `checks/walk-mutate.sh` | sh | **PASS** (0) | PASS (0) | FAIL (1) | YES |
| `checks/wt-sync.sh` | sh | FAIL (1) | FAIL (1) | FAIL (1) | no |

### The four numbers

- **10 of 17 FLIP** between the shebang arm and the python arm. **0 SKIP, 17 of 17 measured.**
- **5 PASS-in-shell are measured FAIL under python**: `bounded-selftest.sh`, `demo.sh`,
  `disarm.sh`, `gen.sh`, `walk-mutate.sh`. *(The brief said two; it is five. The prior unit's
  count came from its `bash` arm, which this measurement shows is not the interpreter.)*
- **`sb-gate.sh`'s REFUSED-3: VISIBLE.** It is one of **3 of 3** `REFUSED` verdicts only the shell
  arm can produce — `sb-gate.sh`, `run-f64.sh`, `substrate-check.sh`. **A shell gate that refuses
  to measure anything can only say so in a shell.**
- **The Python arm's vocabulary over a denominator of 17 is exactly ONE token: `FAIL`.** All 17
  read `FAIL`. **And all 7 "agreements" are that one code** — every one of the 7 is a gate that
  fails in shell *and* is a `SyntaxError` under python, both exiting 1. **0 of 17 agree for a
  reason that is not `SyntaxError`.** An arm with a vocabulary of one over 17 gates cannot
  distinguish agreement from a parse error, and it was measuring the gate population's exit codes.

**The cap moved the count, and both `SKIP`s were gates that genuinely FAIL.** At a 90 s cap the
census read **12 flips of 15 measured**; `checks/run-port-mm.sh` and `checks/e2e.sh` were `SKIP`.
At 420 s (`overcap-portmm.rows`, `overcap-e2e.rows`) both read **`FAIL` after several minutes** and
neither flips — so the settled figure is **10 of 17**, the same denominator with a different
numerator. **A cap is a measurement, not a rounding error, and `SKIP` is not a coin-flip: both
skips hid a real red that took longer than the harness was willing to watch.**

### `rc 127`, and why `charge()` is wrong about it

`checks/disarm.sh:20` defines `say() { print -r -- "$1"; }` and calls bare `print` on 5 further
lines. `print` is a **zsh builtin**; under `bash` it is a command-not-found → **rc 127**, which
`gates/gatekit.py:110`'s `charge()` folds into **`REFUSED`** — "a precondition was absent". The
gate did not lack a precondition; **the gate could not run.** `interp.py:token_of()` names 127
`COMMAND-NOT-FOUND(127)` and refuses to fold it.

### The control that was wrong before I got here

`.agents/slop/exitsurvey/shellentry.py` measured this class on 2026-10-07 and its docstring says
`checks/demo.sh` "answers `rc 0` under `bash` and `rc 1` under `.venv/bin/python`". **9 of the 17
declare `#!/bin/zsh` (8 declare `/bin/sh`), and 5 of those 9 name `zsh` on their OWN usage line**
— `gate.sh` `#   zsh .agents/slop/shlscope/gate.sh`, `lint_demo.sh` `#   zsh checks/lint_demo.sh`,
`run-all.sh` `#   zsh checks/run-all.sh`, `run-f64.sh` `#   zsh .agents/slop/f64/run-f64.sh`,
`run-port-mm.sh` `#   zsh .agents/slop/e2e_port/run-port-mm.sh [workdir]`. **A second, independent
declaration — the usage line — agrees with the `#!` on 5 of 9.** Its `bash` arm **disagrees with
the shebang on 4 of 17** — `disarm.sh` (PASS vs 127), `lint_demo.sh` (FAIL 1 vs 2), `run-f64.sh`
(REFUSED 3 vs 2), `run-port-mm.sh` (FAIL 1 vs 2). **The tree already owned the finding and its shell
half was wrong in the same direction.**

**AND A NUMBER THAT MUST NOT BE CONFLATED.** This unit's settled count is also **10**, and the
brief's was **10** — but they are different measurements. The brief's `10` was *bash vs python*;
this one is ***the file's own `#!` vs python***. They coincide. **Two numbers agreeing for
different reasons is not a cross-check**, and quoting either without its arms invites exactly that
conflation.

---

## 2. THE FIX — by discovery, and it is falsifiable

`gates/gate-surface.py` only. No shell gate was edited.

1. **`interpreter(p)` reads the file's own `#!`** and returns `(argv0, kind, declared, why)`.
   `SHELLS`, `python*`, `node*` — a set of **interpreter names**, and the population is every
   file that declares one. **`env` is resolved, not read at face value**: Linux `#!` puts one
   token after the path and does not run `env` at all, so taking the first token classifies every
   `#!/usr/bin/env X` as `env` and discriminates nothing.
2. **`reach()` uses it**, and returns `how = f"{kind} {argv0} [{why}]"`, which the census **prints
   on every run**: `II PLANT ARM (26 plant(s)): PYTHON …/.venv/bin/python [shebang]`.
   *A plant that runs under the wrong interpreter cannot be distinguished from a FAIL; the only
   defence is for the arm to be visible where the verdict is read.*
3. **The suffix set is gone.** `if p.suffix != ".py": continue` →
   `if interpreter(p)[1] == "SHELL"`. The shell half is now **COUNTED**
   (`II SHELL HALF: 17 entry point(s) ship a SHELL '#!'`) instead of excluded.

**`interpreter()` is NOT FREE, and this is measured.** 8 of the 115 `.py` entry points ship **no
`#!` at all** (`checks/run.py`, `gates/i64-shl-gate.py`, `gates/git-massdelete-gate.py`,
`gates/ew-explog-gate.py`, `gates/i64-shl-oracle.py`, `gates/i64-shr-gate.py`,
`gates/i64-shr-oracle.py`, `checks/test_rewrite_bottom_up_gate.py`). Refusing them would have
been a second regression. So: **shebang first, then the kind this file can otherwise establish**,
and the fallback is a counted line (`II NO SHEBANG: 8 entry point(s)`), never a silent default.

**A regression I introduced and caught: `--plant green` went RED.** My first split was
`if kind != "PYTHON": skip`, which dropped every no-shebang file — 8 live gates **and every
synthetic plant**, so this gate's own `RED_IS="FINDING"` read `UNTAKEN`. **The split is
SHELL-AGAINST-EVERYTHING-ELSE; a file that ships no `#!` is not a shell file.**

### Three plants, because a fix that cannot be falsified is decoration

`--plant green` is **14/14 GREEN** (was 11/11).

- **6a** a `#!/bin/sh` entry point — carrying `VERDICTS = {0: 'PASS'}` **on purpose**, because
  that line is what a Python reader is forbidden to score: in `sh` a spaced `=` is a *command*
  named `VERDICTS`, so a shell gate has no Python declaration and the census must **say so**,
  not report `UNPARSEABLE`. Asserts: run with a SHELL, counted in SHELL HALF, **not** malformed.
- **6b** `#!/usr/bin/env python3` resolves to the **`.venv`** arm — because PATH's 3.14 has no
  `.pth` (`AGENTS.md`), so honouring the literal path would be a quieter instance of this defect.
- **6c** a file shipping **no** `#!` reports `kind NONE` with a reason — never a suffix guess.

---

## 3. THE SIBLING CLASS — by AST, with the denominator

`siblings.py`. **Scope, stated with every number: 951 `.py` files AST-parsed under `checks/`,
`gates/`, `.agents/slop/`.**

| stage | meaning | count |
|---|---|---|
| **A** | `subprocess.{run,Popen,call,check_call,check_output,getoutput,getstatusoutput}`, `os.{system,popen,execv*,spawn*}` call sites, by AST | **575** |
| **B** | sites resolved to a repo entry point | **24** (in 23 files) |
| **C** | **mismatches** | **0 of 24** |

**B is a LOWER BOUND and the file says so.** The 551 unresolved are counted by reason, never
dropped: **`THIRD-PARTY`=334** (a git/`jj`/`cc`/`sha256sum` call with no script argument),
**`UNREAD-ARGV0`=105** (argv[0] built by a helper or an f-string), **`NO-TARGET`=112**.

**What the sibling class actually contains, at 0 mismatches:**

- **`.sh` run as python: 1 site**, `gates/gate-surface.py:311` — and **it is `UNREAD-ARGV0`, i.e.
  invisible to this census.** Section 0.
- **`.py` run as a shell: 0 sites.** The two `SHELL`-at-a-PYTHON-target rows were my own bug.
- **`.mjs` as python: 0 sites**, and **no `.mjs` is in the entry-point population at all** —
  measured: `gates/gates-pop.py:141 SUFFIXES = (".py", ".sh")` cannot see one. **That is a finding
  about the population, not a clean bill.**
- **What IS already right, and is 12 of the 24:** `["./bin/bend", drv]` at 10 sites
  (`checks/differ.py:949`, `checks/e2e.py:375`, `checks/nl-gate-noguard.py:83`, …). A **direct**
  exec; the kernel reads `bin/bend`'s own `#!/bin/sh`. Correct, and the shape my first version
  of the census called a defect.

**Also found, and NOT fixed (another agent owns these files):** `gates/gates-pop.py:141`'s
`SUFFIXES` **is a suffix set** and cannot see an entry point that is neither `.py` nor `.sh`; and
`gates/gates-pop.py:315`'s `entry_reason` branches on `p.suffix` **first**, so its `sh-selfref` /
`sh-dispatch` classes are only reached because the suffix already matched. `gates/gates-pop.py`
itself states that it is *"the one universe this file names by hand."*

---

## 4. BASELINES — all four preserved, all four re-measured after the edit

| command | required | measured |
|---|---|---|
| `checks/nl-gate.py` | rc 0 `AGREE 205/205` | **rc 0**, `AGREE`, `gated 205 agree 205 disagree []` |
| `checks/nl-gate.py --selftest` | rc 3 `REFUSED` | **rc 3**, `== REFUSED, NOT A VERDICT: selftest input absent` |
| `checks/no-txt.py` | rc 0 | **rc 0 at the start of this session; `rc 1` at the end — NOT THIS UNIT.** See below. |
| `gates/gate-surface.py --report` | rc 0 | **rc 0** |

**`no-txt.py` moved under me, and it is not mine.** `rc 0` and `CLEAN` was measured four times
across this session. The final reading is `rc 1` with **3** `.txt` files, all named
`.agents/slop/opsbend-milestone/{check,gate,milestone}.txt` — another unit's directory, which the
same index sweep was holding in stage. **`find .agents/slop/shellgates gates -name '*.txt'` returns
nothing**: 0 `.txt` in this unit's entire write scope. Reported because quoting "rc 0" now would
be quoting a reading that no longer holds, and quoting "rc 1" without the path would be blaming
the wrong tree.

**The census's own numbers are unchanged** — `14 gate(s) declare a surface, 16 unplanted, 0
NO-GREEN, 4 UNOWNED, 10 RENAMED` before and after. Reached-verdicts read **23/42** before my
edit and **22/42** after: the delta is **`gate-surface.py`'s own `--plant green`**, red only while
the no-shebang split regression above was live. `gates/gate-surface.py` (charged) is **rc 1**,
correctly — the census has real unplanted verdicts, and 1 is `FAIL`.

**The population MOVED under me and every number above carries its reading.**
`gates-pop.discover()` returned **130** when `exitsurvey` measured it, **132** at my first
`gate-surface --report`, **133** at my shebang census and **133** at the final one. The
`siblings.py` scope went **946 → 951 `.py` files** and **573 → 575 call sites** across two runs of
the same command. Other units were writing the tree.

---

## 5. FINDINGS THIS UNIT DID NOT FIX, because they are not mine

1. **`checks/sb-gate.sh` names six `.txt` paths** — `:119` `cat $D/rows-bd.raw > $D/rows-bd.txt`,
   then `:134`/`:144`/`:148` read `$D/rows-bd.txt` and `:153` writes `$D/sb-oracle.txt`. **This is
   LATENT, not present**: the gate refuses at `:81` (`$ORACLE` absent) before it ever reaches
   `:100`, and `.agents/slop/schedule-bodies/` currently holds **1 file, `REPORT.md`** — measured.
   The comment above `:119` says *"No `sed` to strip anything"* and then writes a `.txt`, while
   `AGENTS.md` says **"No `.txt` files, ever."** `checks/no-txt.py` exits 0 because it never sees
   the file, and a check that has not seen the defect is not a clean bill. **Reported, not
   edited.**
2. **5 of 17 shell gates `FAIL`/`UNASSIGNED` at `argv=[]` for want of an argument** —
   `classify.sh:19` (`parameter not set`), `plant.sh:26` (`set REPO to`), `substrate-check.sh`
   (*"no files given. A guard invoked with an empty population must not …"*). **An invocation
   artifact, not a gate surface**, and the row says so.
3. **`checks/lintable-gate.sh` FAIL (1)**: *"the probe --check-only says `SOME PROOFS FAIL`"*. That
   is a **genuine** gate red, indistinguishable in shape from `gate.sh`'s UNASSIGNED(2). Nothing
   here distinguishes a real red from a usage refusal except the first line of output.
4. **`checks/wt-sync.sh` FAIL (1)**: `cp: …/.agents/slop/xd1/wt: No such file`. A **missing
   prerequisite exiting 1**, which is `sb-gate.sh`'s `exit 3` shape with the wrong code.

## 7. AN INDEX HAZARD SOMEONE ELSE CREATED — REPORTED, NOT TOUCHED

`.agents/slop/shellgates/{divergence.py,divergence.out,interp.py,siblings.py,siblings.rows}` show
as ` A` in `git status --porcelain`. **This unit staged nothing and committed nothing.** Measured:
`git ls-files -s` gives blob **`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` — the EMPTY blob** — so
these are `--intent-to-add` entries put there by another unit's `git add` sweep, which is also
holding `.agents/slop/quiesce/*` and `.agents/slop/opsbend-milestone/*`.

**Why it is left alone.** `gates/gate-surface.py` is `.M` with index blob `06eacbb3` equal to
HEAD's, so **the actual fix is not staged** — `git status` reads as though it were, which is the
`git ls-tree -r HEAD` vs `git ls-files` trap in its most expensive form. Unstaging is
`git rm --cached`, which would race an in-flight index operation owned by another unit, and this
tree has already lost 66 files and 13,389 lines to exactly that. **Not my index to touch.**

**Why it still needs an owner:** an intent-to-add entry **commits as an empty file**. If that sweep
runs `git commit` before this unit's work is reviewed, `interp.py`, `siblings.py` and
`divergence.py` land as **zero-byte files** and the report's every measurement loses its
instrument. `gates/gate-surface.py`'s plants 6a/6b/6c still fail closed if that happens — they
would catch the *fix* rotting — but the 17-row divergence table would not.

---

## 8. WHAT A READER SHOULD TAKE

**The exit code was never the answer, and neither arm was the question.** `gate-surface.py:311`
had a **vocabulary of one token over 17 gates**; the shell half had **refusals a Python parser
cannot emit**; and the population filter meant none of it was measured anyway. The fix reads the
one declaration a file ships about itself, prints the arm it used on every row, counts the half
it cannot read, and plants all three claims so the next edit has to falsify them.