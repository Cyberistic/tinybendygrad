# MIDRUN — the failure mode the tree has been bitten by twice, built as a test

**UNIT:** midrun. **DATE:** 2026-10-07. **VERDICT OF THE UNIT'S QUESTION:**
a mid-run substrate change on the HOT path **CANNOT** produce a green-looking artifact (12 of 17
pins go red, measured). On the COLD path it **CAN** — and no row in any summary can see it. So the
answer is **both**, and the two halves need different instruments.

Everything below is measured. Where a number could not be taken, it says so.

---

## 0. WHERE THE INSTRUMENTS ACTUALLY LIVE (a citation correction)

The brief names `checks/quiesce.py` and `checks/snapshot.py`. **Neither exists at `checks/`.**

| instrument | real path |
|---|---|
| `quiesce.py` | `.agents/slop/quiesce/quiesce.py` (258 lines) |
| `snapshot.py` | `.agents/slop/quiesce/snapshot.py` (227 lines) |
| the input declaration | `checks/differ.py` (1032 lines) |

`ls checks/quiesce.py` → `No such file or directory`. A brief that cites a path four directories
deep as `checks/` is the exact defect `AGENTS.md` records for `TOOLS.md`: **a governing document
naming a path it does not own.** Flagged, not fixed — `TOOLS.md` is not mine.

---

## 1. THE INPUT SET: IS IT DISCOVERY, OR A LIST?

**Both, in one file, and the split is the finding.**

`.agents/slop/quiesce/snapshot.py:78-86` — the walk:

```python
files = [p for p in (ROOT / "tinybendygrad").rglob("*")
         if p.is_file() and "__pycache__" not in p.parts]
for c in COPIES:
    p = ROOT / c
    if p.is_dir():  files += [q for q in p.rglob("*") if q.is_file()]
    elif p.is_file(): files.append(p)
```

* the **port (140 files)** — DISCOVERY, a directory walk. Correct shape (Doctrine 1).
* the **8 remaining inputs** — `COPIES` at `snapshot.py:63-67` is a **HAND LIST**, with
  `FILES` at `:50-59` carrying `file:line` anchors for each entry and `--declare` asserting the
  anchor line still exists. So the list is *admissible*: it is anchored to the run's own source and
  `--declare` fails when an anchor rots. That is better than a bare list, and it is still a list.

**MEASURED POPULATION: `148` = 140 port + 7 present copies + 1 file under `bin/`.**
(`quiesce --declare` prints `quietness population = 148 paths`, rc=1.)

### 1a. THE TWO ABSENT INPUTS — DECLARATION OR WALK?

**The DECLARATION is right and the WALK silently drops them.** Measured:

```
MISS copy  .agents/slop/graphcmp-dbg.bend    ABSENT ON DISK
MISS copy  .agents/slop/graphcmp-empty.bend  ABSENT ON DISK
MISSING: .agents/slop/graphcmp-dbg.bend ABSENT
MISSING: .agents/slop/graphcmp-empty.bend ABSENT
```

`snapshot.py:162-168` names them and `--declare` exits **1**. But `inputs()` at `:80-85` only
appends `elif p.is_file()`, so the walk returns **148, not 150**, and the two absent paths are
absent from the population **and from the freeze** with no error at build time.

`snapshot.py:76-77` claims: *"A named path that is ABSENT is returned as well (by `--declare`),
never silently dropped."* That sentence is **true of `--declare` and false of `inputs()`**, and
`build()` (`:99`) iterates `inputs()`. **A snapshot that freezes 148 of 150 declared inputs reports
"froze 148 input(s)" and exits 0.**

**AND THIS IS NOT HYPOTHETICAL — IT IS LIVE, RIGHT NOW, IN A PINNED ARTIFACT.**
`checks/differ.py:547` runs the zerorow guard *against the absent file*:

```
$ cat runs/graphcmp/D/D10-zerorow-guard.txt.err
emit bend: 0 rows after 5 attempts -- a FAILURE, not a verdict:
  bend attempt 1: 0 rows, rc=1, stderr tail: SOME PROOFS FAIL Error: -
  message : no such file: .agents/slop/graphcmp-empty.bend
```

`D10-zerorow-guard.txt` is `5` bytes (`rc=1`) and its intended content — the 0-row guard firing
because `graphcmp-empty.bend` *prints nothing* — is indistinguishable from it failing because the
file **does not exist**. `graphcmp.py:1959` raises `SystemExit` for both. **The guard is currently
certifying a missing file.**

No row in `D0-run-summary.txt` reads `D10`'s rc. Checked: `grep -n 'D10\|zerorow' checks/*.py
gates/*.py` → two hits, both the *producer* (`differ.py:290`, `:547`). No consumer. **The plant
whose whole job is to prove a guard fires is itself unfalsifiable.**

### 1b. A THIRD MISSING INPUT — ONE LEVEL UP, AND WORSE

The freeze also omits **`.agents/slop/diffpy/`**, which `checks/differ.py:78` (`check_oracle`)
reads and `ORACLE_PIN` (`:61-64`) pins. It is in neither `COPIES` nor `TOOLING`.

**MEASURED, not inferred:** the first snapshot run died at startup —
`ORACLE DRIFT: diffpy/oracle-run.sh: MISSING -- the frozen oracle is gone`. The snapshot was
unrunnable until I copied the two oracles in by hand.

So the population a run reads has **three** members the freeze does not carry. **The freeze is
incomplete in the same direction three times: a declared-or-pinned input the walk does not see.**

---

## 2. THE REPRODUCTION, ON A SNAPSHOT (never the live tree)

Built with `snapshot.py --build` → `froze 148 input(s)`; toolchain symlinked; `runs/` re-pointed.
Substrate recorded at start: **`e1768f79f1329ffa`** (148 inputs, 0 absent).
Run launched under the required guard:
`.venv/bin/python checks/bounded.py --seconds 420 --mb 2048 -- .venv/bin/python checks/differ.py run`

**VERDICT TOKEN: `WITHIN-LIMITS  rc=1  peak-RSS=355 MB (ceiling 2048)  354s`** — read from the
token, not the exit code (`checks/bounded.py:33-40`). The resource bounds did **not** fire; the
`rc=1` is the run's own `RUN WRONG`.

**THE STAGE BOUNDARY, MEASURED TO THE SECOND.** Break injected into the snapshot's
`tinybendygrad/uop/ops.bend` at **06:22:37**:

| artifact | mtime | bytes | before/after |
|---|---|---|---|
| `D4-cross-range.txt` | 06:22:31 | 5916 | **before** — `VERDICT: DISAGREE` |
| `D5-plant-dtype.txt` | 06:22:34 | **5** | **before** — already zero-row (pre-existing break, §2a) |
| — **06:22:37 BREAK INJECTED** — | | | |
| `D6-matmul-ordered.txt` | 06:23:00 | **5** | after |
| `D7-conf.txt` | 06:23:13 | 14672 | after (pure-python step, unaffected) |
| `D8-dbg-03.txt` | 06:23:14 | **5** | after |
| `D9-stability-group-a.txt` | 06:23:47 | **5** | after |
| `D10-zerorow-guard.txt` | 06:24:18 | **5** | after |

**TOKENS: `5` bytes == `rc=1\n` == `emit bend: 0 rows after 5 attempts` == a compile break.**
Counted over all artifacts written after 06:22:37: **22 zero-row, 6 with content.**

### 2a. AN HONEST CORRECTION TO MY OWN EXPERIMENT

`D1-graph-matmul.txt` (06:19:30) is **also** 5 bytes — but that is **3 minutes BEFORE** my edit,
and `grep -c MIDRUN-BREAK tinybendygrad/uop/ops.bend` on the **live** tree = **0**. So the
snapshot's substrate **already had a compile break** when I froze it (`437>| match idx_u32(axis,
a): … 2438 | case Some{p}` — a real type error in the port, another unit's in-flight work).

**So this run is not a clean single-variable experiment.** It is the *conjunction* of a pre-existing
break and my injected one, and I am reporting it as such. What it still proves, cleanly, is the
thing that matters: **the run went on to write 139 artifacts and a summary, and every stage that
touched the hot path after the break emitted `rc=1`** — the run does not stop, and the *summary is
the only thing that discloses it*. That is precisely `run34`'s shape, and it is why the disclosure
has to be structural rather than a habit.

---

## 3. CAN A RUN DETECT A MOVING SUBSTRATE, OR ONLY BE PROTECTED FROM IT?

**BOTH — and the split is by population, not by instrument.** This is the question that decides
what to land, so it is answered in both directions with a measurement.

### 3a. HOT PATH — DETECTABLE, AND IT IS ALREADY DETECTED. **NO GREEN-LOOKING ARTIFACT.**

The broken run's own summary (`evidence/broken-run-summary.rows`), checked against
`checks/differ.py:243-279` (`PINS`):

```
expect-moved       got=34   want=0        graphs-agree    got=0    want=32
byte-identical     got=0    want=32       not-comparable  got=34   want=0
selfcheck          got=rc=1 want=# SELFCHECK: OK
census-rc          got=rc=1 want=rc=0      stable-pairs    got=0 of 5  want=5 of 5
stable-failed      got=5 of 5 want=0 of 5  plants-disagree got=0 of 7  want=7 of 7
cross              got=0 of 1 want=1 of 1   controls        got=0 of 5  want=5 of 5
oracle-selfcheck   got=      want=# ORACLE SELFCHECK: OK
```

**12 of 17 pins RED.** A mid-run hot-path break is unmissable, and `differ.py:646-651` refuses
the run outright (`RUN WRONG: expect-moved=N`, exit 1).

**AND THE `run34` STABILITY TRAP IS ALREADY CLOSED — VERIFIED AGAINST THE REAL PREDICATE.**
I reproduced the trap: two identical `rc=1` files compare **byte-equal**, so `differ.py:539` takes
the `BYTE-IDENTICAL` branch and `stable-pairs` would count them. The only thing that catches it is
`one_line()` (`differ.py:420`, `<=1 newline`) driving the re-run at `:533` and the
`ONE SIDE IS A 0-ROW FAILURE` row at `:537` — which is why `stable-failed` reads **5 of 5** on my
broken run and **0 of 5** on the healthy one. **The shape check is what defeats "two identical
failures compare equal"; the diff never could.**

*(`differ.py:263-266` records this as the reason for the three counts. The mechanism is real and
I exercised it.)*

### 3b. COLD PATH — **DETECTABLE BY NOTHING THE RUN ALREADY DOES. THIS IS THE GREEN-LOOKING CASE.**

Measured by construction and then confirmed: an edit to `tinybendygrad/PROOF.bend` (not on
`graphcmp.bend`'s import closure) changes **no artifact, no row, no pin** — and still moves the
substrate hash:

```
substrate before cold edit : e1768f79f1329ffa
substrate AFTER  cold edit : d50a2e57b517ad3a
DETECTED by hash           : True
```

**A run can therefore emit a fully green, internally self-consistent artifact set describing a
substrate that no longer exists — and name nothing that would let a later reader notice.** That is
the green-looking artifact, and **it is a provenance failure, not a correctness one.**

**THE ROW THAT WOULD CATCH IT DOES NOT EXIST AND CANNOT BE ADDED AS A COUNT.** A count cannot name
*which* bytes. Only a digest can. → **question 7.**

### 3c. VERDICT

> **Detection, not protection — for the 5 hot files, and `differ.py` already does it.**
> **Protection is the ONLY answer for the 143 cold ones, because there is nothing to detect with.**
> `quiesce.py`'s precondition is **sufficient and correctly scoped**: it certifies the *tree* was
> quiet, which is exactly what protects the cold population. What it cannot do — and what its own
> residual admits (*"A `PASS` CERTIFIES THE PAST, NOT THE NEXT 294 s"*) — is say which bytes a
> finished artifact set belongs to. **Those are two different instruments and both are now here.**

---

## 4. GUARD IN `checks/differ.py`: **NOT LANDED**, and here is the proof

The brief says land one **only if** (3) shows a green-looking artifact. §3a shows it does **not**,
for the population where a guard in `differ.py` could act: 12 of 17 pins already go red.

**A guard there would be a check that cannot fail, which is worse than no check.** Worse still,
`AGENTS.md`: *"a check nobody has ever seen fire is a check of unknown value."*

**AND THERE IS A CONCRETE REASON NOT TO EDIT IT RIGHT NOW, MEASURED:**
`checks/differ.py` mtime **06:21:10**, `git diff --stat` = **90 insertions, 5 deletions** —
**another unit is editing it as I work.** A guard planted into a file mid-edit by a second agent is
a merge conflict dressed as a safety feature. **Reported, not landed.** This is a `REFUSED` on my
own action, which is the honest shape.

---

## 5. THE PLANTED DETECTOR — BOTH STATES, ON A SCRATCH TREE

`.agents/slop/midrun/midrun.py --plant` (pure Python, **no `bend`**, no live tree touched):

```
PASS: all 3 declared inputs unchanged across the run (substrate=693e112b37e6)
PLANT stable  start=693e112b37e6 end=693e112b37e6 step-rcs=[0, 0, 0] -> PASS(0)
  OK: want PASS(0), got PASS(0)
REFUSED, NOT A VERDICT: the substrate moved during the run (693e112b37e6 -> 71b9c9f70f07).
PLANT edited  start=693e112b37e6 end=71b9c9f70f07 step-rcs=[0, 0, 1] -> REFUSED(3)
  OK: want REFUSED(3), got REFUSED(3)
PLANT: OK -- stable substrate PASSes, mid-run edit is REFUSED, never FAILed
```

**WHICH VERDICT AND WHY IT IS THE RIGHT ONE.** The mid-run edit earns **`REFUSED`(3), not `FAIL`(1)
and not `DEAD`(5)**:

* not **`FAIL`** — nothing compared two answers and disagreed. The artifacts are not *wrong*; they
  are *not comparable to each other*. Printing `FAIL` would claim a measurement that was never made.
* not **`DEAD`** — it ran and emitted plenty. `DEAD` is "it ran and emitted nothing"
  (`quiesce.py:26-27`).
* **`REFUSED`** — **a precondition was absent: there was no single substrate to have measured.**
  This is the same reading `quiesce.py:24-25` gives for a moving tree, and exit 3 is gatekit's
  REFUSED (`gates/gatekit.py:59`).

**A detector that cannot say `PASS` is not a detector**, so the stable half is asserted too — a gate
that only ever refuses is a coin that always says no (`quiesce.py:206-207`).

**THE REAL RUN, NOT THE PLANT.** `--verify` against the finished snapshot:

```
START: e1768f79f1329ffa
END  : 99d4ea61a7d13a46  inputs= 148  absent= 0
MOVED: True
```

**Same instrument, same verdict, on 139 real artifacts from a real 354 s run.** That is the
difference between a reproduction and a regression test: the reproduction is §2 (it shows the
failure it already saw); the **regression test is `--plant`**, because it asserts both verdicts and
will fail if either changes.

---

## 6. THE DENOMINATOR — 148 INPUTS, HOT vs COLD, WITH THE SPLIT

The hot path is **the transitive `import` closure of `.agents/slop/graphcmp.bend`** (`:33-37`),
resolved to the port.

**HOT — 5 of 148 (3.4%). Read by EVERY `gc()`/`emit`:**

```
tinybendygrad/LAWS/spec.bend      tinybendygrad/uop/ops.bend
tinybendygrad/helpers.bend        tinybendygrad/uop/render.bend
                                  tinybendygrad/uop/fold.bend
```

*(Method, and its own near-miss: the first walk resolved **5** too but for the wrong reason — it
was blind to `import Base`, the Bend builtin. `Base` is **not** a port file; it is
`references/bend/bend2/base.bend`. Checked before trusting the number — an instrument that cannot
see its population cannot be anything (`AGENTS.md`, Doctrine 1).)*

Plus, on the same hot path but not port files: **`.agents/slop/graphcmp.py`** and
**`graphcmp.bend`** (re-read by every child `gc()` spawns — `differ.py:325-327`), and
**`bin/bend`** itself. **So ~8 of 148 are hot, and these are the CORRECTNESS concern**: read
throughout, so a change changes answers mid-run.

**COLD — 140 of 148 (94.6%):**
* **135 port files** not on the import closure (`PROOF.bend`, `base.bend`, `sz.bend`, `codegen/**`…)
  — walked by the freeze, read by **no** emit. Changing one changes nothing about this run.
* **`checks/differ.py`** — read **once**, at process start. A mid-run edit cannot change the
  running process. *This is the one that bit `quiesce`'s first revision, and it is a snapshot
  concern only.*
* **`checks/devpin.py`** — loaded once, at summary time (`differ.py:708`).
* **the 3 oracle scripts** — `capture()`d once each (`:551`, `:554`, `:558`).

**THE DIFFERENCE THAT DECIDES THE GUARD'S SHAPE, as asked:**

> A **frozen input read once** is a **snapshot** concern — `quiesce`/`snapshot.py` is the whole
> answer and nothing more is needed.
> A **frozen input read throughout** is a **correctness** concern — and §3a shows the run *already*
> refuses it, 12 pins red, because the hot path's answers are visible in the artifacts by
> construction.

**So the guard has no shape to take in `differ.py`: the hot half is already covered and the cold
half is unobservable by design.** What the split actually calls for is a *record*, which is §7.

---

## 7. SHOULD THE RUN RECORD ITS SUBSTRATE? **YES — AND THE COST IS 56 ms.**

`pinindep` proved all 17 pins read a file recording no substrate. Verified: the live
`runs/graphcmp/D/D0-run-summary.txt` carries **`dev=CPU`, `lc_all=C`, `noopt=0`,
`pythonhashseed=0`** — **the environment, and not one byte of the port.** So two artifact sets from
two substrates are **indistinguishable**, and §3b shows a green set can silently be one of them.

**SHOULD `runs/graphcmp/D/`'s OWN SUMMARY CARRY IT? YES**, and the reason is already written in
the file: `differ.py:616-622` records that this summary is parsed as `key=value` by
`gates/retention-check.py`, `checks/corpus-figure.py:140`, `checks/disagree-gate.py:128` and
`checks/env-precond.py`, that **no new parser exists anywhere**, and that *"A separate file would
be a THIRD place the device is claimed."* **One more `key=value` row is therefore free of a new
parser by construction** — and putting it anywhere else would be the mistake that comment warns
against.

**THE COST, MEASURED (5 sweeps of all 148 inputs, 11.3 MB):**

| | |
|---|---|
| one full substrate hash | **min 19 ms · median 28 ms · max 91 ms** |
| start + end | **56 ms** |
| as a fraction of run34's 294 s run | **0.019 %** |
| artifact cost | **one row in a file four parsers already read** |
| what it buys | a later reader can name WHICH substrate produced the artifacts |

**THE SHAPE.** Two rows, not one, because one row is a claim and two are a comparison:

```
substrate-start=<sha256 over 148 paths+bytes>
substrate-end=<sha256 …>
```

Equal ⇒ `PASS`. Different ⇒ `REFUSED`, and the artifacts are not all measurements of one thing.
**A single row cannot be checked by anyone** — it is a label, which is the failure
`differ.py:734-737` (`preconditions_bad`: *"a green row nothing compares to can never go red"*)
exists to prevent. **This is the one recommendation of this report that should be landed, and it is
deliberately NOT landed here — §4.**

**THE ARTIFACT IS THE DIFFERENCE, AND THE MEASUREMENT OF A SUBSTRATE, AND TODAY THIS TREE HAS ONLY
THE FIRST.**

---

## 8. WHAT IS OWNED HERE

| path | what |
|---|---|
| `.agents/slop/midrun/midrun.py` | the detector + `--plant` (both verdicts, asserted) + `--verify` |
| `.agents/slop/midrun/evidence/*.rows` | the broken run's summary / stability / D1.err / D10.err |
| `.agents/slop/midrun/run.err` | the `WITHIN-LIMITS … 354s` guard record |

**Nothing committed. Nothing staged. The live tree was not edited** (`grep -c MIDRUN-BREAK
tinybendygrad/uop/ops.bend` = **0** on the live tree; `runs/graphcmp/D/D0-run-summary.txt` mtime
still 05:45:17). The 12 MB snapshot was deleted after its evidence was kept.

**`bend` was used, once, and only inside the snapshot.** It was checked with `pgrep -f bin/bend`
first and the run was refused twice while another unit held it (`ORACLE DRIFT`, then a contention
window); the reproduction ran with a competing unit present, which does not affect the claim — the
run re-reads the substrate at each `emit` regardless of who else is compiling.

---

## 9. THE RESIDUAL, WHICH IS NOT "NONE"

1. **The freeze carries 148 of 150 declared inputs, and 2 of the 3 pinned-oracle inputs are missing
   entirely** (§1a, §1b). `--declare` names all of them and exits 1; `build()` does not.
2. **`D10-zerorow-guard` is currently certifying a file that does not exist** — a plant with no
   consumer (§1a).
3. **No row anywhere reads a substrate identity**, so a green artifact set cannot be traced to the
   bytes that produced it (§7). One more `key=value` row fixes it at 56 ms.
4. **`checks/differ.py` is under active edit by another unit** (06:21:10, +90/−5), so nothing was
   landed in it (§4). Whoever lands §7 must re-read it first.
5. **This unit's reproduction had a pre-existing break in its substrate** (§2a). The stage boundary
   and the 22-vs-6 count stand; the single-variable claim does not, and is not made.