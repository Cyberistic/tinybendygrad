# HOOK WIRING: WHAT RUNS, WHAT IS ONLY WRITTEN, AND WHAT IS DEAD

`.agents/slop/hooks/REPORT.md`. Every number below was MEASURED on **2026-10-07 06:13–06:40**
by running it, on `.venv/bin/python`. Nothing here is quoted from a document — including
`AGENTS.md`, which is cited only where its own claims are being checked. Instruments:
`_plant.py`, `_wireplant.py`, `_probe_hooks.py`, `_deadpush.py`, `cost.py`. Plant verdicts are
in `plant.out`, `wireplant.out`, `probe.out`, `deadpush.out`, `cost.out`, `runner.out`.

---

## 1. WHAT `wire.py` IS, AND WHICH STATE IT IS IN

**`wire.py` is `.agents/slop/jjreset/wire.py`, 52 lines.** It generates two hooks and installs
them only on `--install` (`:35-48`); a bare run prints a plan (`:46-47`).

| | |
|---|---|
| `BODY` | `.agents/slop/jjreset/wire.py:29-32` |
| `pre-commit` | `… git-massdelete-gate.py staged` (`:30`) |
| `pre-push` | `… git-massdelete-gate.py push "$@"` (`:31`) |

**THE STATE IS "WRITTEN BUT NEVER RUN", NOT "WIRED BUT NOT INSTALLED".** Measured:

- `.git/hooks/` holds **13 files, all `*.sample`**. No `pre-commit`, no `pre-push`.
- `git config --get core.hooksPath` → **rc 1, unset**. `git config --local --list | grep -i hook`
  → **rc 1, no hook keys**. There is no `core.hooksPath` pointing anywhere.
- `wire.py` with no `--install` → `pre-commit: create` / `pre-push: create` / `(dry run…)`,
  **rc 0**, and **writes nothing**.

So nothing is wired and nothing is installed; the generator exists and has never been asked to
emit. The distinction the brief asks for is real and it lands on the worse side: a "wired but
not installed" state is visible in `git config`; **this one is invisible to everything**,
because `git status` does not mention untracked files under `.git/`, no census walks
`.git/hooks/`, and `gates/gates-pop.py:discover()` only walks `checks/` and `gates/`
(`gates/gates-pop.py:320`).

**WHY IT WAS NEVER RUN — and the answer is worse than forgetfulness.** `wire.py:6-8` gives the
reason itself: *"`NOT run by the report: `.git/hooks/` is shared, untracked, and per-clone, so
installing a hook changes behaviour for every concurrent unit."* The instrument declined to
fire, and the report that needed it did not carry the refusal into an install. **A gate whose
installer names its own reason for not installing is a gate with one missing line.**

**AND IT IS IN THE WRONG PLACE, TWICE OVER.** Both the generator (`.agents/slop/jjreset/wire.py`)
and the gate it names (`.agents/slop/jjreset/git-massdelete-gate.py`) live under `.agents/slop/` —
the tree `AGENTS.md` records as being pruned, and the tree `61be7ea90` deleted wholesale.
**Both are git-tracked today** (`git ls-files --error-unmatch` rc 0 on each), so a sweep would
have to be deliberate. But `AGENTS.md`'s own sentence applies verbatim: *"A PATH INSIDE A SWEPT
TREE IS DELETABLE WHILE THE GATE STILL NAMES IT."* And the consequence is measurable:
**`git-massdelete-gate.py` is NOT in `gates/`, so `discover()` CANNOT SEE IT.** 115 entries,
and the guard for the 6167-file catastrophe is not one of them. A runner walking the population
would never invoke it. See §6.

---

## 2. THE HOOKS ARE A DANGEROUS INSTRUMENT — AND FOUR OF ITS FAILURES DO NOT APPLY, AND THE FIFTH DOES

The bodies are **`#!/bin/sh`**, three lines each, one verb.

| the four documented shell-gate failures | applies? | why |
|---|---|---|
| `&&` masking a diff under `set -e` | **NO** | no `&&`, no `set -e`; `exec` is the only verb |
| an `EXIT` trap returning `rm`'s status | **NO** | no trap, no `rm`, no post-command |
| `<( )` not parsing under `sh` | **NO** | no process substitution |
| `${=SUB}` never expanding, hash guard comparing `""` to `""` | **NO** | no parameter expansion at all; and `sh` is not zsh, so the *`${=}`* form is not even in the language |

**The danger is not shell syntax. It is `exec`.** `exec` means the hook's exit status **is**
the gate's exit status, with nothing in between that could mask it — which is correct, and is
also why nothing catches the failure below.

### THE FIFTH FAILURE, AND IT IS NOT A SHELL FAILURE AT ALL: `wire.py:31` IS DEAD

**MEASURED argv on this git** (`_probe_hooks.py`, and reproduced by hand): a `pre-push` hook
receives **`argc=2`** — `$1` remote name, `$2` remote URL — and the refspecs arrive on **STDIN**:

```
argc=2  [1]=origin  [2]=/…/deadpush-remote
--- stdin ---
refs/heads/main 989800e1e31… refs/heads/main 5aa8cc8c18c3…
```

`wire.py:31` generates `… push "$@"`. So `mode_push` is entered with `argv = ("push","origin","<url>")`,
and `git-massdelete-gate.py:238` — `specs = sys.stdin.read() if len(argv) < 2 else argv[1]` —
takes the `len(argv) >= 2` branch and sets `specs = "origin"`. That splits to **one** token,
`len(parts) != 4` is true for the only line, the loop `continue`s, and control falls to
`return PASS` (`:162`).

**MEASURED END TO END, `_deadpush.py` — the guard's own docstring says *"the guard reads the
index for one and stdin for the other"*, and the generated hook makes it read neither:**

```
the pushed commit 66ec5e2d6bab judged DIRECTLY:  rc=3  REFUSED, NOT A VERDICT: … deletes 520 files
installing jjreset's pre-push verbatim
   `git push` rc=0
   hook output: <NOTHING AT ALL>
VERDICT: DEAD. The catastrophe was PUSHED, the hook said nothing, and the exit code was 0.
```

And the contrast, same gate, same hook path, one token removed (`push`, no `"$@"`), on a fresh
540-file deletion:

```
   `git push` rc=1
   REFUSED, NOT A VERDICT: 37555420f596 deletes 540 files / 540 lines -- envelope: normal churn <= 500
```

**ONE TOKEN IS THE WHOLE DIFFERENCE BETWEEN A GUARD AND A DECORATION.** And the failure mode is
exactly the sentence this project wrote: *"a gate that exits 0 having measured nothing is worse
than no gate, because it is trusted."* This one would have been trusted **for precisely the
event it was written to stop** — the mechanism that deleted 6000+ files.

This is the seventh member of `AGENTS.md`'s first-doctrine table, and the first one that is a
**correctness** fault rather than a bookkeeping one: not a list where a population belongs, but
a dispatch that agrees with the wrong thing.

---

## 3. THE MOST IMPORTANT PART: WHICH VERDICT BELONGS IN WHICH HOOK

The brief's question — *"does the hook fire against a tree the author is not changing?"* —
has a **measured yes**, and the answer decides the wiring.

### `msgdiff-gate.py` HAS NO INDEX MODE, AND THAT IS THE WHOLE CONSTRAINT

Its modes are `check <rev>` (`:320`) and `range <rev-list args...>` (`:325`). Both read a commit
that **already exists**: `judge_message` (`:185`) calls `commit_view`, which is
`git ls-tree … <sha>` and `git diff-tree … <sha>`. **There is no `staged` mode and there cannot
be one at pre-commit time, because the commit object does not exist yet.** Its only two ways of
seeing a commit are a sha and a rev-set.

**SO: `msgdiff` CANNOT BE A PRE-COMMIT GATE AT ALL.** Wiring it there does not make it strict,
it makes it *about a different commit*. State D of `_plant.py`, in a scratch clone:

```
D  THE WRONG WIRING -- pre-commit = `msgdiff check HEAD`
   commit rc=1; the gate said: REFUSED, NOT A VERDICT … oracles259/plants.py
   the message being written was: 'a clean commit with no claims whatsoever'
```

HEAD was a bad commit the author was **not changing**. The hook read its message, refused it,
and blocked a clean commit. `git commit` reported failure. **That is a POLICY wearing a hook's
clothes** — and it is precisely the internal call `msgdiff` already made about itself: its first
draft refused 12 of 145, and tightening fixed 11 honest messages rather than finding 12 defects.

### THE FIX IS NOT A FLAG. IT IS THE REV-SET.

**THE SHAPE THAT WORKS — `_plant.py` states E and F, side by side:**

| | command | result |
|---|---|---|
| **GATE** | `msgdiff range <local> --not <remote>` | **PASS(0)** — "range: 1 commits -- 1 PASS, 0 REFUSED" |
| **POLICY** | `msgdiff range <first>..HEAD` | **REFUSED(3)** — forever, including over a brand-new honest commit |

The bad commits are *identical* in both runs. **Nothing was suppressed and nothing was
configured** — `--not <remote_sha>` simply is not in the population. **A pre-existing bad
commit cannot block a new honest one because it is not in the rev-set, not because a flag was
set.** That is the structural answer, and it is why the brief's fear — *"a pre-commit hook that
rejects makes 146 commits unreplayable"* — is true of the policy shape and false of the gate
shape.

### THE VERDICT ASSIGNMENT, AND WHY

| verdict | hook | reads | why there |
|---|---|---|---|
| **mass-delete REFUSED(3)** | **`pre-commit`** (`staged`) | the **INDEX** | the only subject that exists and is being changed. Stops it before it becomes a commit. |
| **force-push REFUSED(3)** | **`pre-push`** (`push`) | the **refspec** | a history-rewriting event is knowable only at push. |
| **msgdiff REFUSED(3)** | **`pre-push`** (`range local --not remote`) | the **NEW commits** | there is no index mode and there cannot be. Judging history at commit time is the policy fault. |
| **DEAD(5) / SKIP(4)** | **neither** | — | neither is a claim about a change. A broken or silent guard must not be able to block or pass a commit. |

### THE FINDING THAT UNDERCUTS ALL OF IT: GIT DESTROYS THE VOCABULARY AT THE BOUNDARY

`_probe_hooks.py` state H, with hooks that exit deliberately and a real `git commit`:

```
   hook exits REFUSED 3 -> `git commit` returns rc=1
   hook exits    FAIL 1 -> `git commit` returns rc=1
   hook exits    DEAD 5 -> `git commit` returns rc=1
   hook exits    SKIP 4 -> `git commit` returns rc=1
```

**`AGENTS.md` already records "a shared number is not a shared vocabulary" for `sb-gate.sh`
and `gatekit.py`. Here the third party is git itself.** REFUSED, SKIP and DEAD are
**indistinguishable** from the exit code the caller receives. The five verdicts survive only if
they are written down somewhere durable — so `pushshim.py` appends the real rc to
`last-verdict.tsv`, and `_wireplant.py` state 4 measures that it works:

```
3  pre-push, bad message in the local set   -> rc=1, "range: 2 commits -- 1 PASS, 1 REFUSED"
4  the verdict FILE                        -> hook  pre-push  3  1 refspec(s)   <- 3 where git said 1
5  honest push over the PUSHED bad commit  -> rc=0                                    <- not blocked
```

---

## 4. WHAT I LANDED, AND WHAT I DECIDED NOT TO DO

**I CHOSE: LAND THE GENERATOR AND THE RUNNER, TRACKED, OUTSIDE `.agents/slop/`'s sweep target
— AND *NOT* INSTALL INTO THIS REPO'S SHARED `.git/hooks/`.**

Four files, all under `.agents/slop/hooks/`:

| file | what it is |
|---|---|
| `wire.py` | generates both hooks; dry run unless `--install` |
| `pushshim.py` | the pre-push adapter: parses stdin refspecs, calls `msgdiff range local --not remote`, records the verdict |
| `run.py` | the single runner; population from `discover()` |
| `cost.py` | per-gate cost with a cap, so "slow" and "hangs" are told apart |

**`wire.py` needs no new gate mode.** `msgdiff`'s `range` forwards argv straight to
`git rev-list` (`:233-238`), so `range <local> --not <remote>` already *is* the pre-push half.
That is why `pushshim.py` is an adapter and not an edit — **I did not touch a gate body.**

### WHY NOT INSTALL HERE — a decision, not an evasion

1. **`.git/hooks/` is per-clone and untracked.** Installing here helps this clone only, is
   invisible to `git status`, invisible to `discover()`, and absent from every other clone.
2. **It is shared by every concurrent unit in this working directory** — `wire.py:6` says so
   itself, and the index reset 5+ times overnight is the measurement of how live that is.
3. **It could not deliver the verdict anyway** (§3): git flattens 3/4/5 to 1.

So the durable artifact is the **tracked generator and runner**; the install is one command,
`.venv/bin/python .agents/slop/hooks/wire.py --install`, and `wire.py` remains a dry run until
a person who owns the shared tree runs it. **Forgetting is no longer the mechanism — the
absence is now a file in git rather than an absence.**

### PLANTED, IN A SCRATCH CLONE — `_wireplant.py`, `--install`, all five states OK

```
1  honest commit through the generated pre-commit      rc=0
2  520-file deletion staged                            rc=1  REFUSED, NOT A VERDICT
3  pre-push, bad message in the local set              rc=1  "1 PASS, 1 REFUSED"
4  the verdict file                                    hook pre-push 3 1 refspec(s)
5  honest push over the PUSHED bad commit              rc=0        <- THE POINT
```

---

## 5. `gate-surface` IS RED BY DESIGN, AND THE RUNNER MUST NOT BE BUILT AROUND GREEN

**THE `--report` EXIT ALREADY EXISTS. NOTHING HAD TO BE ADDED.** `gates/gate-surface.py:400`
defines `--report`, `:287` is `return 1 if (charge and red) else 0`, and `:408-409` wires
`charge=not a.report`. Measured:

```
$ gates/gate-surface.py --report   -> rc=0
$ gates/gate-surface.py            -> rc=1
```

and its own last line names the finding: `GATE-SURFACE: RED -- 13 gate(s) declare a surface,
9/39 verdicts reached, 30 unplanted, 0 NO-GREEN`. **13.3 s** for the first run on this tree,
1.7 s warm.

**HOW A RUNNER SHOULD TREAT A GATE WHOSE REDNESS IS ITS FINDING — three rules, no sixth verdict:**

1. **The runner's verdict is about THE RUN, never about the tree.** Its own exit answers "did
   every gate emit a verdict?", not "is the tree good?". Redness is a **tally**, not a failure.
   A runner that requires GREEN cannot run the instrument that reports unplanted verdicts —
   which is `AGENTS.md`'s *"a pre-commit gate that cannot pass teaches nothing and will be
   skipped"* with the word "pre-commit" removed and nothing else changed.
2. **Ask the auditor to report; never ask it to pass.** `--report` is the documented exit, and
   it is the whole of the answer. **No sixth verdict is invented**, and none is needed: the
   charge flag already separates "this is the report" from "this is a failure".
3. **`RED` must not be `rc != 0`, because that merges SKIP with FAIL.** MEASURED: **7 of the
   14 gates refuse with `input absent`** — they are being honest and they are not wrong.

**AND THE THIRD FINDING, WHICH IS A REAL GAP:** `gate-surface.py` ships **no module-level
`VERDICTS`** (its exits are `0 if not (charge and red) else 1` at `:287` and `2` at `:195`).
**An auditor of surfaces declares none.** So no surface-based filter can see it, and there is
**no declaration anywhere in this tree of "the set of gates whose redness is their finding."**
`run.py` therefore takes `--report-gate=<name>` as an **argument** and prints
`ASKED-REPORT: … NOT IN THE POPULATION (typo, or it moved?)` on a miss, rather than baking a
name into a tuple — a hand list would be the fourth time this project has paid that fault. The
**declaration** is the missing half and it belongs in `gate-surface.py`, which I was told not to
edit; **it is the owner's call and it is the recommendation at the end of this report.**

---

## 6. WHAT A RUNNER MUST INVOKE, AND WHY IT CANNOT BE A LIST

**`coindependent` found 113 entry points; `gates/gates-pop.py:discover()` finds 115 as of
06:40.** It has been 113, then 114 (06:13), then 115 — because `gates/tn_mul-gate.py` and
`gates/tn_mul-oracle.py` **were written at 06:20 while I was measuring.** Quote that with the
timestamp or not at all.

**A RUNNER MUST WALK `discover()`. Reading a list is the hand-list fault this project has
removed three times**, and `gates/gates-pop.py:90` already admits `HOMES = ("checks","gates")`
is "a list, and it is admitted". The live demonstration above is the argument: **a list written
twenty minutes ago was already wrong.** `run.py` walks `discover()` and never names a gate.

**THE FILTER IS ALSO A DISCOVERY, NOT A LIST.** A gate is invoked iff its source declares a
`VERDICTS` mapping, read with `ast.literal_eval` off the module body — **read as SOURCE, never
imported**, because importing a gate RUNS it and `gates/mixin-op-gate.py` exits 2 at module
scope. **MEASURED: 13 of 115 declare one.** The other **102 are reported SKIP with the reason**,
because a gate whose surface nobody has written down cannot be tallied, and a silent omission
is how a gate becomes "written but never run" without anyone noticing.

**AND THE POPULATION CANNOT SEE THE GUARD FOR THE CATASTROPHE.** `git-massdelete-gate.py` is
under `.agents/slop/jjreset/`, outside `HOMES`, so it is **not in the 115**. A runner that
trusts the population would never invoke the mass-delete guard at all. **`discover()` is blind to
every gate outside `checks/` and `gates/` — the same structural blindness one level down that
`AGENTS.md` records for the `.txt` census.** See the recommendation below.

---

## 7. THE COST OF THE RUNNER EXISTING

**MEASURED, `cost.py`, 45 s cap, 14 gates (`cost.out`, `cost.tsv`):**

| | |
|---|---|
| 13 of 14 gates, **combined** | **4.1 s** |
| `checks/residue.py` | **OVER-CAP at 45 s, SILENT** — it `os.walk`s the whole tree |
| an uncapped runner | **exceeded 600 s** before the cap existed |

So the runner is cheap **except for one gate that never finishes**, and without a cap it is
unbounded. **The cap is therefore a SKIP, not a DEAD**: `residue.py`'s cost is UNKNOWN, which
is not evidence it is broken and is certainly not evidence it passed.

**WHAT IT DOES WHEN A GATE CRASHES — the mapping, explicitly.** `gatekit.py:60`:
`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`, **and no sixth verdict.** `run.py` adds
three *rules*, not verdicts:

| condition | mapped to | measured reason |
|---|---|---|
| exit 0 **with output** | **GREEN** | — |
| exit 1 **with** `Traceback` in output | **DEAD** | `checks/oracle_f64.py` with no argv raises `IndexError` at `:266` and exits **1 — the same number as FAIL**. A runner reading `rc==1` as "ran and got the wrong answer" reports a **crash as a verdict.** |
| exit 1 **without** a traceback | **FAIL** | — |
| exit 3 | **REFUSED** | `61be7ea90` → 3; `00b101574` → 3 |
| exit 4 | **SKIP** | unknown mode; bare invocation |
| exit 5 | **DEAD** | `check refs/heads/nope` → 5, `DEAD: git could not answer: …` |
| **any other** exit | **DEAD** | not a verdict, so never a pass |
| exit 0 **with no output** | **DEAD** | *"exited 0 having said nothing"* — measured: a gate that prints 0 bytes and returns 0 is GREEN under `all(rc==0)` and is exactly the sentence |
| over cap | **SKIP** | cost UNKNOWN |

**TWO TRAPS IN THE OBVIOUS AGGREGATORS, BOTH MEASURED:**

- **`rc == 1` as the RED condition is BLIND TO BOTH GUARDS.** `msgdiff-gate.py` and
  `git-massdelete-gate.py` return `FAIL` from **one line each** (`:305`, `:218`), **both
  inside their own `--plant` self-test.** Their refusals are **3**. A runner that watches for 1
  sees two permanently-green guards.
- **`check` WITH NO ARGUMENT JUDGES HEAD AND PASSES.** `msgdiff-gate.py:321` is
  `sha = argv[1] if len(argv) > 1 else "HEAD"`. So
  `.venv/bin/python gates/msgdiff-gate.py check` → `PASS: HEAD -- 0 deletion claims checked`.
  **A runner that invokes it bare gets a confident verdict about an unrelated commit.** Bare
  invocation *with no mode at all* is SKIP(4) and is honest; `check` with no rev is neither.

### THE RUN, AND ITS DENOMINATOR — `runner.out`

```
POPULATION: gates-pop.discover() -> 115 entries, 24 modules
INVOKABLE : 13 declare VERDICTS; 102 do not (SKIP, no surface to tally)
  GREEN 3  FAIL 2  REFUSED 7  SKIP 1  DEAD 1
THE DENOMINATOR, WHICH IS NOT THE TALLY: 5 of 14 gates reached a verdict about the tree.
```

**"14 gates ran" is 14 subprocesses, not 14 measurements.** That sentence is the cost of a
runner nobody trusts, stated as a number.

---

## 8. WHAT I DID NOT CHANGE, AND THE THREE THINGS THE OWNER SHOULD DECIDE

I was told not to edit gate bodies, `AGENTS.md`, `checks/differ.py`, or `tinybendygrad/`, and
not to commit. So, in order of how much they cost:

1. **`.agents/slop/jjreset/wire.py:31` — delete `"$@"`.** One token. MEASURED: with it, a
   520-file deletion is pushed and the hook says nothing; without it, the same push is REFUSED.
   **This is the highest-value edit in this report and it is a deletion, not an addition.**
2. **Move `git-massdelete-gate.py` into `gates/`.** Its `ROOT = parents[3]` (`:52`) has to
   move with it. Until then **`discover()` cannot see the guard for the catastrophe**, which is
   the population blind spot in §6.
3. **Give `gate-surface.py` a module-level `VERDICTS`, and declare the auditors.** One constant
   next to `:130`'s `DECL`, and it closes the last discovery gap: a runner would then find the
   auditor by the same rule that finds everything else, and `--report-gate` could go away.

**AND ONE THING FOR THE LEDGER.** `.agents/TOOLS.md` should record that
**`git commit` and `git push` both collapse every non-zero hook exit to 1.** It is the third
party in `AGENTS.md`'s "a shared number is not a shared vocabulary" finding, it is measured,
and no document in the tree currently says it.
