# `wireit` — one shared call, seven live readers

**Unit:** `wireit` · **Scope:** the 8 reader instruments of `runs/graphcmp/D`
**Date:** 2026-10-12, measurements taken 20:05–20:40 local.
**Committed nothing. Staged nothing.** `.git/index` sha256 `8e9f1839…cc0bbc` identical before and after this
unit's runs (measured, below).

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG FIRST, WITH THE BEFORE-VALUE

Three times, all in this unit, all the same class.

**(a) A clean confident zero from a broken instrument.** My independent census's first run printed:

```
instruments scanned : 0   READERS : 0   WRITERS : 0
```

on a tree with 189 `.py` in `checks/` + `gates/`. Cause: **three `dirname` calls where four are needed** —
`.agents/slop/wireit/verify-readers.py` sits four levels below the root, so `ROOT` resolved to `.agents`.
This is verbatim the failure the brief names, and I reproduced it before finishing reading the brief.
Fixed by four `dirname`s **plus an assertion that guards the computed `ROOT`** — because my first guard
asserted against `dirname(__file__)` (which is `.agents/slop/wireit`, never holding `checks/`) and
therefore fired on the *correct* root too. An assertion that cannot fail on the right answer is a second zero.

**(b) Then 5 readers and 0 writers, where the truth is 7 and 1.** Still confidently clean, still wrong.
Isolated to one binding: their resolver returned `ROOT = '..'`, mine returned `None`. Cause:

> `Path(__file__).resolve().parents[1]` parses as a `Subscript` whose `.value` is a **bare
> `ast.Attribute`** — `parents` is a *property*, not a method. It is **not** `Call(func=Attribute(attr='parents'))`.

My `Subscript` branch required the `Call` form, so it was **dead code**, `ROOT` resolved to `None`, and
**4 readers plus the only writer** fell out of the census while every other number stayed tidy.

**(c) `$?` after a pipe is the pipe's exit.** `env-precond … | tail -5; echo rc=$?` reported `rc=0`
while the gate actually returned **3**. Re-measured with the output redirected to a file: `check rc=3`,
`record rc=3`. Same trap a second time: a `for` loop over `while read -r c; do … python $c …` reported
`rc=2` for seven readers, because **zsh does not word-split an unquoted parameter expansion** — `$c`
reached Python as one filename. With `${=c}` the same seven report `3,0,3,0,3,3,0`.

**None of these were visible as failures. All three looked like answers.**

---

## 1. THE POPULATION, MEASURED TWICE, AND THE DENOMINATOR IS 189 NOT 188

`checks/runs-artifacts.py`'s own census, run 20:12:

```
artefact set        : runs/graphcmp/D   (named by checks/differ.py:42, the generator)
tracked in git      : 0 of 241 on disk
instruments scanned : 189
WRITERS             : 1  ['checks/differ.py']
READERS             : 8  [corpus-figure, devpin, diary-census, differ, disagree-gate, env-precond, no-txt, retention-check]
live state          : ARTIFACTS-STALE  exit=3  ... 116.6 h old, over the 24.0 h limit
```

**Denominator 189, not the 188 in the brief** — one instrument was added to the tree between the brief
being written and me running it. Every number above is *of 189 instruments walked* (`checks/*.py` +
`gates/*.py`), read 2026-10-12 20:12 local.

I then wrote an **independent** AST census, `.agents/slop/wireit/verify-readers.py`, which does **not
import `checks/runs-artifacts.py`** — a shared resolver is exactly what hides a shared bug. After fixing
(a) and (b) it converges exactly: **9 readers including SELF → 8 excluding SELF, 1 writer, 189 scanned**,
with the same 23 differ.py sites, 10 env-precond sites, 5 devpin sites. The brief's list of 8 is
**confirmed**, by two independent resolvers, at denominator 189.

### 1a. BUT ONE OF THE EIGHT CANNOT TAKE THE CALL: `checks/diary-census.py` IS A PLANT FIXTURE

The three sites (`diary-census.py:502,521,532`) are **all inside `plant()`**, and they pass the path to
`readers_of("runs/graphcmp/D", t3)` against a **`scratch()` tree**. The one non-plant use is
`main():15`, `rel = a.readers_of.rstrip("/")`, and `--readers-of` has **no default** (`:334`). The file
**never opens `runs/graphcmp/D` and never stats it** — it scans *source files* for readers of a
directory the user names.

So it is a **false positive of the reader census**, the same class the brief flags for
`gates/gendirs.py`, sitting inside a list the brief hands me as settled. The brief told me not to
rediscover `sweep.py` (docstring) and `substrate-id.py` (dead binding); **this is a ninth correction it
did not list.**

> **THE TRUE LIVE-READER COUNT IS 7 OF 189, NOT 8.** `checks/diary-census.py` is left untouched.

---

## 2. WHAT IS WIRED, AND HOW

**One shared call**: every reader loads `checks/runs-artifacts.py` **by path** and calls its `require()`
— the same idiom `checks/sweep.py:101` already uses (`spec_from_file_location("runs_artifacts", …)`), so
there is **no second copy** of the vocabulary or of the census. `require()` returns `0` on `FRESH` and a
non-zero code otherwise, printing the token on stdout and the remedy on stderr.

| reader | exit before (absent) | exit after | why |
|---|---|---|---|
| `checks/disagree-gate.py` | **2** | **3** | was colliding with *usage* in 2 other readers |
| `checks/env-precond.py` | 3 (per-**file**) | **3** (per-**directory**, first) | `p.exists()` on a file whose directory may be gone |
| `checks/corpus-figure.py` | 1 (**FAIL**) | **3** | "the port is wrong" vs "this gate cannot see" |
| `checks/devpin.py` | 1 (**FAIL**) | **3** | `D.glob()` over an absent dir reported **0 files** |
| `gates/retention-check.py` | 1 or **0** | **3** | `report()` returns a bool; a stale corpus printed `RETENTION: OK` |
| `checks/differ.py snap` | 0 | **3** | `snap` reads the run already on disk |
| `checks/no-txt.py` | 0 | **0, state reported on stderr only** | see §4 |
| `checks/diary-census.py` | — | **untouched** | plant fixture; cannot take the call (§1a) |

Two readers already spoke exit 3 (`disagree-gate` — *"REFUSED IS EXIT 3 AND IT OUTRANKS FAIL"*, `:501`;
`env-precond` — `REFUSED = 3`, `:77`), so the wiring extends a vocabulary the tree already had rather
than inventing one.

### Deliberate asymmetries, stated rather than hidden

- **`differ.py run` and `repro` are NOT gated.** They *write* `runs/graphcmp/D`. Requiring the generator
  to find its own output fresh would make `ARTIFACTS-STALE` answered by the one command that clears it.
  Only `snap`, a pure read, is guarded. This is the generator/reader split stated in code.
- **`disagree-gate --lane citations` is NOT gated** — that lane takes no `tree` and reads the PIN file.
  Gating it would refuse a lane measuring something else. Measured: still `rc=0`.
- **`--plant` is NOT gated** in `differ.py` / `devpin.py`: a plant asserts the opposite outcome against
  the instrument, so it is a self-test, not a measurement. Measured: both still `rc=0`.

---

## 3. THE CONTROL, DRIVEN — NOT ASSERTED

`.agents/slop/wireit/wiring-plant.py` builds **four real directories** under a `TemporaryDirectory` and
runs each reader's **real `main()` in a real subprocess**, then reads the token it printed and the exit it
returned. Expected tokens come from the **shared call's own output**, so the reader is proved to *pass the
answer through*, not to agree with me. `runs/graphcmp/` is never touched — the way to honour "nothing may
delete it" is not to write a test that does.

```
THE SHARED CALL ALONE (checks/runs-artifacts.py --plant):
  absent  ARTIFACTS-ABSENT  exit=3  OK      empty  ARTIFACTS-EMPTY   exit=5  OK
  stale   ARTIFACTS-STALE   exit=3  OK      fresh  ARTIFACTS-FRESH   exit=0  OK
  distinct tokens across the four states: 4  OK

EVERY READER THAT ACCEPTS A SUBJECT OVERRIDE, THROUGH ITS REAL main():
  disagree-gate    absent ARTIFACTS-ABSENT rc=3 OK     empty ARTIFACTS-EMPTY rc=5 OK
                   stale  ARTIFACTS-STALE  rc=3 OK     fresh ARTIFACTS-FRESH rc=0 OK
  retention-check  absent ARTIFACTS-ABSENT rc=3 OK     empty ARTIFACTS-EMPTY rc=5 OK
                   stale  ARTIFACTS-STALE  rc=3 OK     fresh ARTIFACTS-FRESH rc=1 OK

THE CONTROL: absent and stale must not share a token
  disagree-gate    4 distinct tokens  OK
  retention-check  4 distinct tokens  OK
wiring-plant: all states OK          rc=0
```

**The decisive property holds: an absent subject and a stale subject do not produce the same token.**
They share exit 3 on purpose — both are a missing precondition — and are separated by token and remedy,
because the operator's next action differs (regenerate vs "the green you are reading is old").
`DEAD` (5) is spent on **present-but-empty**, per the brief's corrected verdict; `SKIP` (4) is never used.

`FRESH` falling through to the reader's **own** verdict (0 for `coverage`, 1 for `retention-check`) is the
proof the guard does not swallow a real result.

**Scope of the drive, stated honestly:** all four states are driven end-to-end through the **two** readers
that accept a subject override. The other five have no override, and moving `runs/graphcmp/` to manufacture
one is the one thing I was told never to do. Their branch coverage therefore comes from the shared call
(4/4, driven) plus their own live observation (§5), and their pass-through is a `return code` on the
`ra.require(...)` result. **I did not drive all four through all seven, and I am not claiming I did.**

---

## 4. THE ONE READER THAT CANNOT TAKE A SHARED CALL, AND WHY

**`checks/no-txt.py`.** Its site (`:109`) builds the **exempt name set** from `differ.declared()`; its
only filesystem touch is `os.path.exists` per name (`:132`). **It never reads an artefact's content**, so
its verdict — *how many hard `.txt` the project owns* — is **invariant** under the set being absent, empty,
stale or fresh. Absence is in fact the **safe** case: the names being exempted do not exist, so there is
nothing to wrongly exempt.

Gating it would make the `.txt` police **refuse to police whenever the corpus went stale**, which is
backwards, and would break the mandated `rc=0`. So it **reports on stderr only**, never charging the exit
and never touching stdout (which callers parse). Measured: `rc=0`, stdout byte-identical to before,
stderr carries `note: ARTIFACTS-STALE (not charged to this gate's exit; …)`.

---

## 5. VERIFICATION — every rc, this session

| check | rc | note |
|---|---|---|
| `checks/no-txt.py` | **0** | stdout unchanged; state on stderr |
| `checks/nl-gate.py` | **0** | `gated 205  agree 205  disagree []`, `AGREE` |
| `checks/census.py` | **0** | |
| `gates/gate-surface.py --report` | **0** | `II SHELL HALF: 18` |
| `checks/disagree-gate.py --lane citations` | **0** | ungated by design |
| `checks/index-arm-gate.py` | **3** | `.git/index` sha256 **identical** before/after |
| `checks/runs-artifacts.py` | **3** | `ARTIFACTS-STALE`, 116.6 h |
| `runs/graphcmp/` | — | **241 files, newest `10/07 23:50`** — untouched |
| `wiring-plant.py` | **0** | 4/4 states × 2 readers + shared call |

Every touched reader, live subject: `differ snap` **3**, `differ plant` **0**, `disagree --lane coverage`
**3**, `--lane citations` **0**, `env-precond` **3**, `corpus-figure` **3**, `devpin` **3**,
`devpin --plant satisfied` **0**, `retention-check` **3**, `no-txt` **0**.
`--help` parses `rc=0` for all six CLI readers. Diff: **7 files, +128 −13**.

Untouched, as instructed: `checks/runs-artifacts.py`, `checks/sweep.py`, `AGENTS.md`,
`checks/diary-census.py`. Nothing staged; `git diff --cached` not used.

---

## 6. WHAT STILL BLOCKS — AND IT IS NOT WHAT THE BRIEF THOUGHT

The brief calls the blocker "a ~178 s `bend`-class run". **Running it would have destroyed evidence.**

The brief also asserts *"`flip` still emits 6 rows on both lanes byte-identically."* **Measured, that is
false on the live tree:**

```
runs/graphcmp/D/D2-canon-bend-flip.txt   0 bytes   0 rows
runs/graphcmp/D/D2-canon-py-flip.txt   370 bytes   6 rows
D2-cmp-flip.txt: flip NOT COMPARED: py=370 bytes bend=0 bytes
                 (a 0-byte side is a FAILURE, not a pass)
D1-graph-flip.txt.err: emit bend: 0 rows after 5 attempts -- a FAILURE, not a verdict:
   Location: argstr 410 | def argstr(a: O.Arg, depth: U32) -> String: 411>|
   match a: | ^^^^^^^^ 412 | case O.ANone{}: "N"
```

The bend lane did not disagree on `flip` — **it emitted nothing, five times**, which is the **DEAD**
state, and `gates/retention-check.py` independently reports `IV stable-failed=5 of 5 (expected 0 of 5)`.
A re-run against that substrate would have **overwritten the only copy of 241 artefacts, 0 of them in
git**, with a fresh set carrying the same failure.

**Two facts change the recommendation, and I measured both:**

1. **The blocker may already be fixed.** `.agents/slop/graphcmp.bend` has mtime **`10/12 16:27`** — today —
   against the artefact's `10/07 23:41`. The `argstr` that failed to parse is **gone**: line 410 is now
   `def blobstr(...)`. Another unit rewrote it.
2. **I still did not run it, and the reason is the sum-precondition, not caution.**
   `.agents/slop/peakrss/census.rows` (dated `10/07 23:26`) covers the **138 port `.bend` files** under
   `tinybendygrad/` and holds **`grep -c graphcmp` = 0 rows** — **no peak RSS for the file that would run**.
   `hw.memsize` is 16.0 GB, so the 60% ceiling is 9.6 GB; the known heavy cases (`sz` 1,108 MB,
   `nir` 1,152 MB) fit, but **the corpus driver's peak is simply not in the table**, and the table is
   itself 5 days stale for a file that changed today. **The rule is to use that table, not a remembered
   number — so the precondition cannot be evaluated, and I name the blocker instead of guessing.**

**What unblocks it, in order:** (a) a `--plant`-shaped check that `graphcmp.bend` *parses* — cheap, no
corpus run, and it would have caught this weeks earlier; (b) one sequential `checks/differ.py run` with
nothing else compiling; (c) a peak-RSS row for `.agents/slop/graphcmp.bend` added to `census.rows`, so the
next unit can evaluate the sum-precondition instead of citing this report.

**The staleness is now answerable and acted on by seven instruments. Nothing runs the remedy — and
nothing can, safely, until (a) exists.**

---

## 7. WHAT I WOULD CHANGE WITH WIDER SCOPE (not touched)

1. **The loader boilerplate is duplicated 7×** (~4 lines each). I was scoped to the 8 readers and could
   not add a shared module, so "one shared call" means one shared *call*, not one shared *loader*. A
   `checks/artefact-guard.py` would collapse both.
2. **`checks/runs-artifacts.py`'s docstring is stale against its own code**: it says *"read by 12
   instruments"* (line 7) and *"10 of 188"* (line 336); the code measures **8 of 189**. Two of its own
   numbers are three and one generations out. I did not edit the file.
3. **`census()` counts plant fixtures as readers.** `diary-census.py` (and `gendirs.py`) name a
   directory in a code position without opening it. A `--live` flag, or excluding sites inside
   `plant()`, would make the reader count mean what its name says.
4. **`_env`'s last-binding-wins tie-break is load-bearing for the only writer.** `checks/differ.py:1091-1113`
   uses `global D` / `live = D` / `D = Path(td).resolve()` / `D = live` — a **save/restore idiom**. Whether
   the census sees `checks/differ.py` as a writer at all depends on the order a fixed point happens to
   visit statements; two resolvers on the same tree disagreed here until the `parents` spelling was fixed.
   **The population's stability rests on an unstated tie-break.**