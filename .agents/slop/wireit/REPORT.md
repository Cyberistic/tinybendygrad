# `wireit` — one shared call, wired into the readers that can take it

**Unit:** `wireit` · **Scope:** the reader instruments of `runs/graphcmp/D` · **Date:** 2026-10-12.
**Committed nothing. Staged nothing.** `.git/index` sha256 byte-identical across every run of
`checks/index-arm-gate.py` below (measured, §7).

> This report supersedes the earlier `REPORT.md` in this directory, which was written before the
> server restart by the previous attempt of this same unit. It claimed "7 readers". **The number
> is 5.** §1 is why, and it is the most important thing here.

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG FIRST, WITH THE BEFORE-VALUE

Four times, all in this unit, all the same class: an instrument that could not see its population
returning a clean, confident, wrong number.

### (a) A clean confident zero from a broken resolver — **BEFORE: `READERS : 6`, `WRITERS : 0 []`**

My independent census (`verify-readers.py`, written not to import `runs-artifacts.py`, because a
shared resolver hides a shared bug) printed:

```
instruments scanned : 189     READERS : 6      WRITERS : 0  []
```

on a tree whose true answer is 8 readers and 1 writer. **The writer it missed is
`checks/differ.py` — the only author of the subject.** Two causes, both mine:

1. **`Subscript` over `Attribute`, not over `Call`.** `Path(__file__).resolve().parents[1]` puts
   `parents` on an `Attribute`; my branch tested `isinstance(v, ast.Call)`, which is false for
   that shape. So `ROOT` resolved to `None` in `corpus-figure.py`, `disagree-gate.py`,
   `env-precond.py` and `differ.py`, and **every path derived from it resolved to `None`**.
2. **A prefix comparison that could not match.** `under()` compared `p[:2]` against
   `TARGET.split("/")` — a 2-element prefix against a 3-element target, so it was `False` for
   *every* input. Once `TARGET` grew to `runs/graphcmp/D` the whole census was structurally
   incapable of matching anything.

**The lesson, and it is the one this file exists to record: a broken instrument is
indistinguishable from an empty tree.** Both print a number. Only the number's *shape* gave it
away — `WRITERS : 0` on a tree whose subject has an author is not a plausible answer, and I
checked it instead of shipping it.

### (b) A control that could not reach its own fixture — **BEFORE: all four states read `ARTIFACTS-STALE`**

My first `control.py` created four scratch roots and ran each reader with `cwd=<scratch>`. Every
reader anchors `ROOT = Path(__file__).resolve().parents[1]` — measured, all five — so `__file__`
was the **live** tree and `cwd` was ignored. The output was:

```
absent=3/ARTIFACTS-STALE  empty=3/ARTIFACTS-STALE  stale=3/ARTIFACTS-STALE  fresh=3/ARTIFACTS-STALE
```

**Every state reported the live corpus, four times.** I was one sentence away from writing that
the wiring collapses all four states into one token — the exact defect I was sent to fix — when in
fact the control had never built the state it claimed to build. **A control that cannot reach its
fixture measures the tree it was aimed away from, and it measures it cleanly.** The fix is to copy
the reader itself into each state tree so its own `ROOT` lands on the fixture.

### (c) Three fixture gaps that produced crashes indistinguishable from verdicts

`8 of 20` probes died at `rc=1` — the same code as "the pins disagree" — because the copied tree
lacked `.agents/slop/graphcmp.py` (loaded by `corpus-figure.py` *and* by `differ.py:110 corpus()`,
which `retention-check.py:343` calls), `gates/gatekit.py`, and `gates/gendirs.py`. The last one
is worth its own line: `retention-check` answered `rc=1  gates/gendirs.py is gone -- it IS the
discovered population, and a check whose population is missing must not report 0`. **That is the
reader being correct and my fixture being wrong** — it is the same shape as the guard under test,
refusing over a population it cannot see. A fixture that trips the defect it is meant to measure
has to be completed before its numbers mean anything. `probe()` now records `CRASH` so a
traceback can never be scored as a verdict again.

### (d) `grep` ate two exit codes

`cmd 2>/dev/null; echo rc=$?` reported `rc=0` for a run that printed `FAILED`, and a
`py_compile` loop printed `COMPILE FAIL` for five files that all compile. **Twice in one
session.** Every rc in §7 is read without a pipe.

---

## 1. THE DENOMINATOR, AND WHY THE BRIEF'S 8 IS THE WRONG NUMBER

The brief's list of 8 is **correct for the 8 files it names**, and I can reproduce it. It is
wrong as a count of what takes the shared call, because **two of the eight do not read the
subject** — and one of the eight I should have counted was itself.

Measured 2026-10-12, by two independent AST resolvers that now agree:

| | denominator | scope |
|---|---|---|
| instruments scanned | **189** → **190** | `checks/*.py` + `gates/*.py`, a directory walk |
| readers of `runs/graphcmp/D` | **9** | incl. `checks/runs-artifacts.py` itself |
| …minus SELF (its own docstring: a census grows by one when added) | **8** | `runs-artifacts.py:SELF` |
| writers | **1** | `checks/differ.py:42` |

**The 8 readers:** `checks/corpus-figure.py`, `checks/devpin.py`, `checks/diary-census.py`,
`checks/differ.py`, `checks/disagree-gate.py`, `checks/env-precond.py`, `checks/no-txt.py`,
`gates/retention-check.py`.

**Of those 8: 5 are wired. 3 are not, for reasons that are MEASURED, not assumed** — §2.

---

## 2. THE 3 THAT GENUINELY CANNOT TAKE THE SHARED CALL

Each was tested by **running it against a fixture where the directory is absent**, not by reading
its code and forming an opinion.

### `checks/diary-census.py` — a SOURCE SCANNER, not a corpus reader

Its three AST sites are arguments to its own `readers_of()`, i.e. it names `runs/graphcmp/D` as
**data to scan for readers**. Proven on a temp tree with no `runs/` at all:

```
temp tree has runs/graphcmp/D ? False
readers found WITHOUT the directory existing: ['checks/a.py']
```

It answers correctly with the subject absent. A staleness guard there would refuse a tool that
works.

### `checks/no-txt.py` — a CARVE-OUT over declared NAMES

Its dependence is **inverted**. `graphcmp_artifacts()` builds 352 exempt paths from
`differ.declared()`, which is a pure name computation: *"the `.txt` files `differ.py` DECLARES it
will write"*. That is exactly true when they are absent and false when they are present-but-different.

**A staleness guard in `no-txt.py` would make the `.txt` rule unenforceable precisely when the
corpus is stale** — the carve-out is most needed exactly when the directory has been swept and
someone has re-created a `.txt` by hand. This is the one wiring that would have been actively
harmful, and the argument for it was "it is one of the eight".

### `checks/differ.py` — the WRITER, and it creates the state

`differ.py:42` is the generator. `state()` must not guard the run that produces the subject; that
is a circular precondition, not a check. It is the **1 writer** and is counted as a reader only
because `snap`/`repro`/`plant` also read.

---

## 3. THE ONE SHARED CALL, LOADED BY PATH

No second copy. Each wired reader does the same 4 lines, and `require()` returns the exit:

```python
spec = importlib.util.spec_from_file_location("runs_artifacts", str(ROOT / "checks/runs-artifacts.py"))
ra = importlib.util.module_from_spec(spec); spec.loader.exec_module(ra)
if code := ra.require(prefix, root=str(ROOT), label="<gate>", remedy=ra.REGENERATE):
    return code
```

`gates/retention-check.py` already did this and is the template; `checks/sweep.py:101` loads the
same module the same way (`generated_read_dirs()`). **A population declared by the generator's
own module, loaded by path** — the shape the rules ask for.

### The vocabulary, and why absent is `REFUSED` not `DEAD`

`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` is not invented here: it is
`gates/gatekit.py:60`, read by `gate-surface.py` **by path** and printed as
`0=PASS, 1=FAIL, 3=REFUSED, 4=SKIP, 5=DEAD -- the OWNER, by path`.

| state | exit | token |
|---|---|---|
| absent | **3** | `ARTIFACTS-ABSENT` |
| present, zero files | **5** | `ARTIFACTS-EMPTY` |
| present, older than `MAX_AGE_S` | **3** | `ARTIFACTS-STALE` |
| present, fresh | **0** | `ARTIFACTS-FRESH` |

Absent ⇒ `REFUSED` is the brief's own instruction and the tree's: `checks/substrate-id.py:65`
— *"A gate whose DEAD is reached by the wrong cause is still a gate that cannot say why"* —
and `:70`, of a gate that had it right by accident. `DEAD` is spent on **present-but-empty**,
the one case where the gate ran, reached its reader, and got nothing back. `SKIP` is deliberately
unused: this always measures or refuses.

---

## 4. THE CONTROL — DRIVEN, NOT ASSERTED

`.agents/slop/wireit/control.py`, `rc=0`. Each reader is invoked **exactly as an operator invokes
it**, as a subprocess, in a tree containing a **copy of itself** so its own `ROOT` is the fixture.
The token is read back off stdout; **nothing compares against a literal I typed.**

```
checks/corpus-figure.py (default)      absent=3/ARTIFACTS-ABSENT empty=5/ARTIFACTS-EMPTY  stale=3/ARTIFACTS-STALE  fresh=1/ARTIFACTS-FRESH
checks/devpin.py (default)             absent=3/ARTIFACTS-ABSENT empty=5/ARTIFACTS-EMPTY  stale=3/ARTIFACTS-STALE  fresh=1/ARTIFACTS-FRESH
checks/disagree-gate.py --lane pin     absent=3/ARTIFACTS-ABSENT empty=5/ARTIFACTS-EMPTY  stale=3/ARTIFACTS-STALE  fresh=2/ARTIFACTS-FRESH
checks/env-precond.py --check          absent=3/ARTIFACTS-ABSENT empty=5/ARTIFACTS-EMPTY  stale=3/ARTIFACTS-STALE  fresh=3/ARTIFACTS-FRESH
gates/retention-check.py (default)     absent=3/ARTIFACTS-ABSENT empty=5/ARTIFACTS-EMPTY  stale=3/ARTIFACTS-STALE  fresh=1/ARTIFACTS-FRESH
disagree-gate --lane citations         absent=2/-  empty=2/-  stale=2/-  fresh=2/-   EXEMPT (different subject)
--control: every reader distinguishes ABSENT / EMPTY / STALE / FRESH by TOKEN
```

**The decisive property holds: absent ≠ stale, and `ARTIFACTS-EMPTY` has its own exit 5.**
`fresh` exits differ per reader (1/1/2/3/1) because **the guard does not flatten each gate's own
verdict** — that is the point of returning rather than overwriting.

The harness also refuses a silent reader (`absent` with no token) and a reader that says `FRESH`
with an exit outside the vocabulary.

### And the real bug the control found: `gates/retention-check.py`

**The guard was below the work it guards.** `main()` ran `registry()` → `differ.declared()` →
`differ.py:110 corpus()` → load `.agents/slop/graphcmp.py`, *then* called `require()`. With the
corpus absent that chain raised, and the gate answered **`rc=1` with a traceback** — not
`REFUSED`, and indistinguishable from "the retention clauses failed".

I hoisted the guard above `registry()`/`report()`. **A guard placed after the work it guards is a
comment.** This gate passed `ARTIFACTS-STALE` on the live tree and would have failed only on a
corpus that was gone — the failure mode is invisible to every test that does not delete the thing.

### The second harness, and why there are two

`wiring-plant.py` (also `rc=0`, pre-restart) drives `disagree-gate --tree` and
`retention-check --dir` — the readers that accept a **subject override**, through their real
argument paths. `control.py` drives the five **default-argument** readers. They cover different
code and agree.

---

## 5. REFUSED IS DISTINGUISHABLE FROM SKIP AND FROM "CHECKED AND FINE"

A caller reading only `$?` gets `3` for a refusal, `5` for dead, `0` only when the corpus is
FRESH. On the **token line**, stdout vs stderr are separated by destination:

```
$ .venv/bin/python checks/devpin.py
devpin: ARTIFACTS-STALE  runs/graphcmp/D: newest artefact is 116.6 h old, over the 24.0 h limit, and it is read as current     <- stdout
devpin: this is not a pass: the reader would measure nothing over an empty population                                             <- stderr
devpin: remedy: .venv/bin/python checks/differ.py run   # writes runs/graphcmp/D/ (0 of its files are in git)                    <- stderr
rc=3
```

`SKIP` (4) is never returned by any of the five: they measure or refuse. `checks/env-precond.py`
declares `VERDICTS = {0: "OK", 1: "FAIL", 2: "REFUSED"}` and `no-txt.py` `{0: "CLEAN", 1: "RED"}`;
adding exit 3 introduces **no** `UNOWNED`/`RENAMED` finding, because `gate-surface.py:515` charges
only codes a gate *declares*, and a subset declaration is not a superset one.
`gates/gate-surface.py --report` is `rc=0` after the wiring.

### A prior refusal removed: `checks/disagree-gate.py:471` returned **2**

Absent used to exit `2` — a **private exit outside the tree's vocabulary**, undocumented, and
colliding with `env-precond`'s declared `2: "REFUSED"` for a different meaning. Now 3.

---

## 6. THE STALENESS — WHAT STILL BLOCKS IT, ANSWERABLE AND NOT ACTED ON

Live state, measured: `ARTIFACTS-STALE`, newest artefact **116.6 h** old against a 24 h limit,
read as current. 5 gates now refuse on it instead of reporting numbers over it.

**The remedy is `.venv/bin/python checks/differ.py run`. I did not run it.** What I did instead:

- **The frozen oracle is NOT the blocker.** `ORACLE_PIN` (`differ.py:61`) read **BY ARTIFACT NAME**,
  both sha256s recomputed and **both MATCH**: `oracle-run.sh` `94e7108d…`, `oracle-repro.sh`
  `a5d23505…`. All 17 `PINS` load.
- **The memory precondition is satisfied, with numbers.** `graphcmp.bend` (1,674 lines) imports
  five port files whose peaks are in `.agents/slop/peakrss/census.rows`:
  `uop/ops.bend` **345 MB** · `uop/fold.bend` **484 MB** · `uop/render.bend` **204 MB** ·
  `helpers.bend` **204 MB** · `LAWS/spec.bend` **2 MB** = **1,239 MB**, against a budget of
  **9,830 MB** (60 % of `hw.memsize` 16 GiB). **`sz ‖ sz` (1.1 GB each) is not in this set**, so
  the sum-precondition is met with ~8.6 GB of headroom.
- **The blocker, stated exactly:** **`graphcmp.bend` itself appears 0 times in the 138-file peak-RSS
  census.** The five inputs are measured; the file `differ.py:950` actually runs
  (`./bin/bend .agents/slop/graphcmp.bend --check-only`) is **not**. So the headroom is a lower
  bound on the inputs alone and the one file that matters has no measured peak. `bin/bend` exists
  (2,097 bytes). Under the rules I cannot supply that number by running it, and the census is the
  instrument that would: **one row, `graphcmp.bend`, under `checks/bounded.py --mb`**, then the
  remedy is unblocked and nothing else is.

**What still blocks it, in one line:** the staleness is fully diagnosed and now loudly refused by
5 gates; the only unmeasured quantity is the peak RSS of one 1,674-line `.bend` file, and no
instrument has ever measured it.

---

## 7. EVERY rc, READ WITHOUT A PIPE

| command | rc | reading |
|---|---|---|
| `checks/no-txt.py` | **0** | no `.txt` created; 0 in `.agents/slop/wireit/` |
| `checks/nl-gate.py` | **0** | `IDENTICAL (205 shared)` on both lanes |
| `checks/census.py` | **0** | `reached BOTH: 70`, `WALLS: []` |
| `gates/gate-surface.py --report` | **0** | no `UNOWNED`/`RENAMED` introduced |
| `checks/disagree-gate.py --lane citations` | **0** | unaffected |
| `checks/index-arm-gate.py` | **3** | `REFUSED, NOT A VERDICT` — **`.git/index` sha256 `8e9f1839…cc0bbc` byte-identical before and after** |
| `checks/runs-artifacts.py` | **3** | `ARTIFACTS-STALE` |
| `checks/runs-artifacts.py --plant` | **0** | 4 distinct tokens across 4 states |
| `.agents/slop/wireit/control.py` | **0** | §4 |
| `.agents/slop/wireit/wiring-plant.py` | **0** | §4 |
| `checks/differ.py plant` | **0** | `PLANTS: GREEN (4/4)`, over a COPY |
| `py_compile` × 5 readers | **0** | all compile |

**`runs/graphcmp/` untouched: 241 files, newest `10/07 23:50`, `git ls-tree -r HEAD` → 0.**
Never moved, deleted or `rm -rf`'d. The plants use `TemporaryDirectory`; `differ.py plant` says so
in its own output: *"no `bend`, no write into runs/graphcmp/D"*.

**Untouched as instructed:** `checks/runs-artifacts.py`, `checks/sweep.py`, `AGENTS.md` —
`git diff HEAD` empty for all three. `checks/no-txt.py` and `checks/diary-census.py` also
unmodified (they are §2's non-participants).

---

## 8. REPORTED, NOT FIXED — THINGS I WOULD RATHER CHANGE

1. **`checks/sweep.py:180-193 const()` cannot resolve a single modern path spelling, and
   `self_output_dirs()` returns 1 directory on a tree of 188 — MEASURED, just now:**
   `self_output_dirs() -> 1 ['.agents/slop/residue']`. It handles `Constant`, `Name`, and
   `os.path.join`; it has **no `BinOp`** (so `ROOT / "x"` — **751 `ast.Div` occurrences of 2,723 `BinOp`, measured 2026-10-12
   by AST over `checks/*.py` + `gates/*.py`** — resolves to nothing), **no `Attribute`**, **no `Subscript`** (so `Path(__file__).resolve()
   .parents[1]` resolves to nothing — the §0a defect, shared), and it **counts `open` as a
   write**, so a reader's `open(p)` is charged as an output. Left alone as instructed: it feeds
   `house_excluded`, which guards the citation corpus. **It should be fixed by someone who can
   afford to re-derive that corpus** — and the cheapest correct fix is to point it at
   `runs-artifacts.py`'s `sites()`, which resolves all of these.
2. **`runs/graphcmp/` is untracked, unsweepable and unrecoverable.** `checks/sweep.py:72` puts
   `runs` in `RESIDUE_ROOTS`, so a sweep is *entitled* to delete 241 files that git cannot restore,
   and nothing in the sweep path consults `runs-artifacts.py:unrecoverable_dirs()` even though
   that function is exactly the answer. **The sweep is entitled to destroy the subject and nothing
   tells it not to.**
3. **`checks/env-precond.py` and `checks/devpin.py` already exited 3 before this unit.** Their 3
   meant "the pins disagree". **Two gates have been using the REFUSED code for a FAILURE**, which
   is the ambiguity this unit removes — worth knowing that the code was never unambiguous.
4. **`checks/diary-census.py` takes > 200 s** on the default lane and produced no output in that
   time. It walks every `.py`/`.md` including `.agents/slop`. Not a hang; a census nobody runs.
5. **The index is stale and dangerous right now.** `checks/{corpus-figure,devpin,disagree-gate,
   env-precond}.py` and `gates/retention-check.py` appear in `git diff --cached` **holding their
   PRE-wiring content** (0 occurrences of `ra.require`) while `HEAD` and the working tree hold
   the wired version (2). **A bare `git commit` would revert all five.** I did not touch the index;
   `index-arm-gate` moved `stale=1, deletion=0` → **`stale=8, deletion=5`** during my session
   while its own sha256 stayed unchanged under my runs — **another unit is writing.**

---

## 9. THE FILES

- `.agents/slop/wireit/control.py` — drives all 5 default readers × 4 states, copies the reader.
- `.agents/slop/wireit/verify-readers.py` — independent AST census, does not import the shared one.
- `.agents/slop/wireit/wiring-plant.py` — drives the 2 subject-override readers.
- Wired: `checks/{corpus-figure,devpin,disagree-gate,env-precond}.py`, `gates/retention-check.py`.