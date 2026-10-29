# PLANT THE SIX — 16 UNPLANTED VERDICTS, 6 GATES, 0 LEFT

**HEAD at measurement:** `ac4c8888a` (the "before" run was at `b90b15999`; one unrelated commit by
another unit landed in between — see §7). **Method:** `.venv/bin/python` only, no `bend`, no
`git add -A`, no directory staged. Committed by path with `git commit --only -F <msgfile> -- <paths>`.

**INSTRUMENT:** `gates/gate-surface.py`, read-only. It was NOT edited.

---

## 0. THE HEADLINE, AS TWO NUMBERS FROM THE INSTRUMENT ITSELF

| | verdicts declared | reached by a declared plant | UNPLANTED | MISPLANT | NO-GREEN |
|---|---|---|---|---|---|
| **BEFORE** (`b90b15999`) | 70 | 45 | **16** | 9 | 0 |
| **AFTER** (`ac4c8888a`) | 70 | **64** | **0** | 6 | 0 |

`GATE-SURFACE: RED -- 22 gate(s) declare a surface, 64/70 verdicts reached, 0 unplanted, 0 NO-GREEN,
4 UNOWNED exit code(s), 10 RENAMED exit code(s)`

**THE 6 REMAINING MISPLANTs ARE PRE-EXISTING AND NOT MINE** — `checks/no-txt.py` (1),
`gates/gate-surface.py` (2), `gates/pyvals-gate.py` (1), `gates/txt-carveout-gate.py` (2). **Every
one of them is in the BEFORE run too, and NONE is one of my six gates.** MEASURED, by set
difference of the two runs' `RED … UNPLANTED|MISPLANT` lines: **19 lines removed, 0 lines added.**
No row went from `RESOLVES` to `UNPLANTED`/`MISPLANT`.

**⇒ AND 9 OF THE 19 REMOVED LINES BELONG TO GATES THAT ARE NOT MINE.** `checks/dup-gate.py`,
`checks/norm_check.py`, `checks/oracle_f64.py`, `gates/upstream-pow-dtype-gate.py` and
`gates/upstream-promo-lattice-gate.py` had plants in the working tree at the AFTER run that they
did not have at the BEFORE run — MEASURED: `git diff --stat HEAD -- <file>` shows +25/−4,
+23/−6, +57/−8, +41/−17 and +17/−3 respectively, i.e. **another unit was editing those five gates
CONCURRENTLY**. Those five improvements are **THEIRS** and I did not commit their files.
**MY SIX GATES ACCOUNT FOR 10 UNPLANTED + 2 MISPLANT = 12 ROWS, AND ALL 12 ARE GONE.**

### THE PER-GATE TABLE, MY SIX ONLY

| gate | declared | reached BEFORE | reached AFTER | UNPLANTED+MISPLANT BEFORE | AFTER | class BEFORE | class AFTER |
|---|---|---|---|---|---|---|---|
| `checks/dup-census.py` | 0/3 | **3** | **0/3** | 1 | **0** | UNTAKEN | FAILURE |
| `checks/env-precond.py` | 0/1/2 | **0/2** | **0/1/2** | 1 | **0** | FINDING | FINDING |
| `checks/gate.py` | 0/1/3 | **3** | **0/1/3** | 2 | **0** | UNTAKEN | FAILURE |
| `checks/hermetic-census.py` | 0/3 | **(none)** | **0/3** | 2 | **0** | UNTAKEN | FAILURE |
| `checks/nl-gate-noguard.py` | 0/1/3 | **(none)** | **0/1/3** | 3 | **0** | UNTAKEN | FAILURE |
| `checks/nl-gate.py` | 0/1/3 | **(none)** | **0/1/3** | 3 | **0** | UNTAKEN | FAILURE |

**⇒ AND EVERY GATE MOVED OUT OF `UNTAKEN`.** `UNTAKEN` is *"the gate has never been seen agree, so
its red cannot be a failure of the tree"*. All six now have a **demonstrated green** — the census
itself says `undeclared and green was demonstrated` — so their reds are chargeable, which is the
whole point of planting them.

---

## 1. THE PLANTS, ONE ARGV PER MISSING VERDICT, AND WHY THAT ARGV REACHES IT

All 17 plants verified by EXECUTION (declared rc == observed rc), not by reading.

### `checks/dup-census.py` — `VERDICTS = {0: "OK", 3: "REFUSED"}`, `PLANTS = {3: []}`

**ADDED: `PLANTS[0] = ["--one", "oracles/tinybendygrad_renderer_nir_llvmir.bend.rows"]`**

**WHY IT REACHES 0.** `--one FILE` is this gate's OWN documented mechanism for naming a lane (the
docstring's second usage line), and it reaches `main()`'s census over the named file. The refusal
that used to sit above it is **CONDITIONAL**: it fires on the missing `CACHE` (`checks/lanes/`,
absent from git), and `--one` names a lane **instead of** the population, so the census runs.
MEASURED: **rc 0**, and the census is **not vacuous** — *205 rows read, 205 accepted, 201 distinct
keys, the reader's own loss 4, attributed as `4` `=`-in-a-name, and `RECONCILES`*. The file it
reads is the **PRE-RENAME** lane, so the loss it reports is the `=`-class the rename closed, and it
is a WITNESS as well as a plant.

**⚠ AND THE PLANT HAD TO BE MADE NON-DESTRUCTIVE FIRST.** `main()` ended with an unconditional
`(HERE / "dup-census.json").write_text(...)`. MEASURED 2026-10-29: `--one <that file>` returned 0
and left `checks/dup-census.json` at **10 insertions / 62,250 deletions** against HEAD — the
tracked 797,251-byte population census **overwritten by a one-lane census**. That is the same
destruction `.agents/slop/denominator/REPORT.md` §1 measured through the *other* route (an absent
`CACHE`), and the artifact is the census **of the population**, so `--one` does not publish it.
**A GATE THAT RUNS A PLANT MUST NOT REWRITE THE TREE IT IS PLANTED IN.** The fix is the guard
`if not a.one:` — one line, and it changes no verdict.

`PLANTS[3] = []` is UNCHANGED and still reaches 3: `checks/lanes/` is absent, so the population
census REFUSES.

### `checks/env-precond.py` — `VERDICTS = {0: "OK", 1: "FAIL", 2: "REFUSED"}`, `PLANTS = {0: [...], 2: [...]}`

**ADDED: `PLANTS[1] = ["--plant", "moved-only"]`**

**WHY IT REACHES 1.** The gate's `--plant` mode already EXISTS and already runs a plant whose
whole subject is a **moved** precondition (`_one_plant(move_summary=True)` reads `noopt=1` against
a declaration of `noopt=0`). MEASURED: that plant exits **1**. **BUT `plant("moved")` ITSELF
EXITS 0** — it is a REPORT on five plants, and every one of them behaved — so `--plant moved` does
NOT reach 1 and the verdict had no argv.

**⇒ SO A THIRD KIND WAS ADDED, AND IT WEAKENS NOTHING.** `moved-only` runs the **SAME five
plants with the SAME fixed expectations and the SAME `bad` list**, and then exits with **the
moved-summary plant's own measured exit** (1) instead of 0. The only thing that differs is
**which number the process exits with**, and that number is one this file **MEASURED** on a
fabricated tree — never one the caller named. This file's own docstring forbids the alternative
("an argument that changed the expected exit would let a caller make this file pass by asking for
the wrong thing"); `moved-only` changes the process's exit, **not** the expectation table.
MEASURED: `--plant satisfied` → 0, `--plant moved` → **0 (UNCHANGED)**, `--plant moved-only` → 1,
`--plant nonsense` → 2.

### `checks/gate.py` — `VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}`, `PLANTS = {3: []}`

**ADDED: `PLANTS[0] = ["--plant", "clean"]`, `PLANTS[1] = ["--plant", "broken"]`,
`PLANTS[3] = ["--quick", "--tree", "checks/absent-dtype.js"]`**

**WHY 0 AND 1 NEED A NEW PLANT AT ALL.** The gate already ships the mechanism: `--tree PATH`
(*"runs a copy instead of the live file, which is how the plants run"* — its own docstring). But
**no argv over a TRACKED file reaches rc 1**: MEASURED, every historical copy of `dtype.js` this
tree carries (`.agents/slop/dotfix/scratch/runtime/dtype.js`,
`.agents/slop/ropfix/tinybendygrad/runtime/dtype.js`,
`.agents/slop/expandfix/scratch{,-before}/runtime/dtype.js`) is a **FIXED** revision, and
`--quick --tree` over each answers **rc 0, MISMATCH 0**. **A GATE WHOSE RED IS UNREACHABLE
CANNOT SHOW THAT IT CAN GO RED, AND A GATE THAT HAS NEVER GONE RED HAS NO GREEN TO HAVE FALLEN
FROM.** So `--plant` was added, and it **uses the gate's own `--tree`**: `--plant clean` builds
the copy from the live bytes; `--plant broken` builds it with **ONE anchored value changed** —
`fp8_decode`'s own line `if ((x & 0x7f) === 0) return (x & 0x80) ? 0x80000000 : 0;` → `…
0x80000001;` — which is the SIGN-BIT-ONLY change that makes the port disagree with CPython on the
negative zero of every format. MEASURED: **rc 1**, `MISMATCH 2` (`D[e4m3][c80]`, `D[e5m2][c80]`),
and the LIVE tree answers MISMATCH 0 → **rc 0**.

**⇒ AND THE ANCHOR IS WHAT MAKES THE PLANT HONEST:** if the anchor line is ever removed from
`dtype.js`, the plant **REFUSES (3)** rather than exiting 0 on an uncorrupted copy and calling it
a PASS. **THE PLANT WRITES NOTHING ON THE TREE** — the corrupted copy lives in a TEMPORARY
DIRECTORY and the live file is only read.

**⚠ AND `PLANTS[3]` CHANGED, BECAUSE `[]` BECAME A MISPLANT.** The old `PLANTS[3] = []` claimed
that bare argv refuses — and it DID, because the driver `checks/drive.mjs` was swept by
`371cc64c9` and is not in git. **THE DRIVER IS NOW RESTORED** (§4), so bare argv answers 0 and
`PLANTS[3] = []` became a **false claim**. The refusal that IS reachable is the gate's own rule
applied at the read site: `--tree` **names an input**, and an absent input is **REFUSED (3)**, not
a traceback. MEASURED: `--quick --tree /nonexistent/dtype.js` answered `== DEAD: the node driver
failed, rc=1` and exit **5** before the check — **the wrong word for an absent input** — and
`== REFUSED, NOT A VERDICT: input absent: … (named by --tree)` and exit **3** after it.

### `checks/hermetic-census.py` — `VERDICTS = {0: "OK", 3: "REFUSED"}`, `PLANTS = {}`

**ADDED: `PLANTS[0] = ["--check", "--only", "allred"]`,
`PLANTS[3] = ["--check", "--only", "allred", "--out", "checks/rows/absent"]`**

**WHY 0 REACHES 0.** `--check` re-emits a graph and byte-compares it against the PUBLISHED row
set. On `allred` the published set reproduces → **rc 0**. MEASURED: **1.9 s**. **THE PLANT IS ONE
GRAPH ON PURPOSE** — the whole corpus is 35 graphs × 2 processes, and `gates/gate-surface.py`
runs every plant on every census. **IT IS NOT VACUOUS:** `--check` reads 10 published rows for
`allred` and compares them byte-for-byte against a fresh emission, and `70/70` over the whole
corpus also answers 0 (MEASURED).

**WHY 3 REACHES 3.** `--check` reads `out/rows-<name>-<side>.rows`; a file that is not there is
`ABSENT`, which is a disagreement, and the check answers **3**. MEASURED: `# STALE allred/py:
ABSENT` / `# STALE allred/bend: ABSENT` → **rc 3**. **THE PATH IS INSIDE THIS GATE'S OWN
PUBLISHED DIRECTORY** (`checks/rows/`), and it is a subdirectory that does not exist and never
will — so the plant depends on **no temporary directory, no other unit's fixture, and no
gitignored file**. ⚠ AND IT IS NOT A TRAP FOR A FRESH CLONE: the published sets are **TRACKED**
(`git ls-tree -r HEAD -- checks/rows/` = 71 files), so `--out checks/rows` alone answers 0 on
every checkout.

**⚠ AND THE PREVIOUS REVISION'S CLAIM WAS FALSE.** It said *"no argument of any shape gets past
[the refusal]"* — but the refusal is **CONDITIONAL** (it fires only when `isolate.py` is ABSENT),
and with `isolate.py` restored every argv reaches the census.

### `checks/nl-gate.py` — `VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}`, `PLANTS = {3: []}`

**ADDED: `PLANTS[0] = ["--port-stdout", "gates/cstyle-live.rows", "--oracle-stdout",
"gates/cstyle-live.rows"]`, `PLANTS[1] = ["--port-stdout", "gates/cstyle-live.rows",
"--oracle-stdout", "oracles/tinybendygrad_renderer_cstyle.bend.rows"]`, `PLANTS[3] = ["--selftest"]`**

**WHY 0 AND 1 ARE HERMETIC, AND WHY THAT MATTERS.** The old declaration said *"this gate refuses at
MODULE SCOPE, above every `argparse` … so no argument of any shape gets past it"* — **TRUE WHEN
WRITTEN, FALSE NOW**: `.agents/slop/rebase-gate.py` AND `.agents/slop/nl/nl-oracle.py` are both
PRESENT, so argv reaches `main()`.

**⇒ AND THE PLANTS ARE HERMETIC ON PURPOSE.** This file's own header records that
`tinybendygrad/uop/ops.bend` is in this port's 6-file import closure and is owned by another live
unit: MEASURED, two consecutive captures printed 206 rows and then ZERO, naming `vd_text` and then
`vd_dbg.of`. **A PLANT THAT READS THE LIVE PORT IS A PLANT THAT CAN ANSWER "NO ROWS" INSTEAD OF A
VERDICT** — and this gate's `--selftest` already refuses on an absent capture for exactly that
reason. So both plants read **tracked files** instead: `gates/cstyle-live.rows` is the gate
family's own tracked fixture, and `oracles/tinybendygrad_renderer_cstyle.bend.rows` is the lane
it was captured against.

MEASURED: **`PLANTS[0]` → rc 0** (`port 227 / oracle 227` names, `gated 227   agree 227
disagree []`, `AGREE`, **0.2 s**, no `bend`). **AND IT IS NOT VACUOUS** — GUARD 0 (the name-set
reshape check) runs on both lanes and finds nothing, and 227 values are compared. **`PLANTS[1]` →
rc 1**, `9 gated row(s) DISAGREE and every one is NAMED: ['tmap BASE', 'tmap CLANG', 'tmap CUDA',
'tmap METAL', 'tmap OPENCL', 'wmma 16_16_128 fp8', 'wmma 16_16_16 half', 'wmma 16_16_16 i8']` —
**a REAL disagreement between two TRACKED lanes of this tree** (the cstyle lane's
`fp8e4m3` → `float8_e4m3` dtype-NAME rename and its `wmma` rows), so the plant exercises the
value comparison rather than a fabricated disagreement. It also exercises GUARD 0's other half:
the two lanes disagree about the NAME SET (`kern BASE  lb=1` vs `kern BASE  lb 1`).

**WHY 3 REACHES 3 NOW.** `PLANTS[3] = []` became a **MISPLANT** for the same reason as
`checks/gate.py`'s: the oracle is present, so the module-scope refusal does not fire and bare argv
answers 0. The refusal that IS reachable is this gate's OWN: `--selftest` needs the captured port
lane `checks/nl-port-post.txt`, which no commit carries, and it **REFUSES (3)** rather than
running a control over a fixture that is not the fixture. MEASURED: **rc 3**,
`== REFUSED, NOT A VERDICT: selftest input absent: …/checks/nl-port-post.txt`.

### `checks/nl-gate-noguard.py` — `VERDICTS = {0: "AGREE", 1: "BROKEN", 3: "REFUSED"}`, `PLANTS = {3: []}`

**ADDED: the same two `--port-stdout`/`--oracle-stdout` plants, and
`PLANTS[3] = ["--port-stdout", "checks/absent-lane.rows"]`**

**WHY 0 AND 1 ARE THE SAME ARGV AS `nl-gate.py`'s.** The two files are the gate and its CONTROL,
and they share the reader by construction. MEASURED: **`PLANTS[0]` → rc 0** (`gated 227   agree
227   disagree []`, `AGREE`, 0.2 s, no `bend`, no live port) — **and the green is not vacuous: the
gate reads 227 names with `rebase-gate.py:rows()` and COMPARES 227 values, and the rc-1 plant
below is the SAME comparison over two lanes that differ.** **`PLANTS[1]` → rc 1**, `gated 181
agree 172   disagree ['tmap BASE', 'tmap CLANG', 'tmap CUDA', 'tmap METAL', 'tmap OPENCL', 'wmma
16_16_128 fp8', 'wmma 16_16_16 half', 'wmma 16_16_16 i8']`, `BROKEN`.

**⇒ AND `PLANTS[3]` REQUIRED A REAL FIX TO THE GATE, NOT JUST A NEW ARGV.** The gate's only
refusals were the module-scope ones, which are **filesystem-conditioned** and cannot be reached
by argv. MEASURED: `--port-stdout /nonexistent/file.rows` answered a **`FileNotFoundError`
traceback and exit 1** — **THE SAME EXIT AS A DISAGREEMENT**, so "the capture I was told to read
is not there" and "the port and the oracle DISAGREE" were one number to a reader of `$?`. **THIS
FILE'S OWN `refuse()` SAYS WHY THAT IS WRONG**: *"a gate that crashes where it should refuse
cannot distinguish 'the input is absent' from 'I am broken'"*, and `checks/abi_gate.py`'s rule is
that a missing input is REFUSED (3) and not a verdict at all. **⇒ SO THE READ IS CHECKED BEFORE IT
IS TAKEN**, at the read site (the module-scope refusal above it is about the tree; this one is
about the two NAMED INPUTS). MEASURED: **rc 3**,
`== REFUSED, NOT A VERDICT: input absent: checks/absent-lane.rows (named by --port-stdout)`.

---

## 2. WHAT I DID **NOT** DO, AND WHY

**⇒ I DID NOT NARROW A SINGLE DECLARATION.** Every `VERDICTS` mapping is **byte-identical** to
HEAD. Nothing was withdrawn to make a count go down. MEASURED: the `VERDICTS` literals are
unchanged in all six files.

**⇒ I DID NOT EDIT `gates/gate-surface.py`.** It is the instrument and I am one of the rows it
reads.

**⇒ I DID NOT ADD A NEW PLANT MODE WHERE THE GATE HAD NO MECHANISM, EXCEPT IN TWO PLACES, AND
BOTH ARE REPORTED BELOW.**

### 2a. `checks/env-precond.py` — a NEW `--plant` KIND (`moved-only`)

The gate **already had** the `--plant` mechanism (argparse `choices=["satisfied","moved"]`), and
`moved-only` is **a third kind of the existing mode**, not a new mode. **It changes the PROCESS's
exit, not the expectation table** — the same five plants, the same fixed expectations, the same
`bad` list, and `--plant moved` still exits 0. **REPORTED** because it is an extension of the
gate's argv surface.

### 2b. `checks/gate.py` — a NEW `--plant` MODE (`clean` / `broken`)

The gate already had `--tree PATH` (*"which is how the plants run"*), and the plant **uses it**:
it builds the tree and hands it to the gate's own comparison. **REPORTED** because it is a new
argv word. **It was NECESSARY**: no argv over a tracked file reaches rc 1 (§1).

### 2c. `checks/gate.py` — `checks/drive.mjs` RESTORED (a NEW TRACKED FILE)

**⇒ THIS IS THE ONE CHANGE OUTSIDE MY SIX GATES, AND IT IS THE GATE'S OWN INPUT.**

`checks/gate.py` refused at module scope with *"input absent: …/checks/drive.mjs (this gate's
driver; its last home was `.agents/slop/jsfp8/drive.mjs`, moved by 3f0e70ff1 and swept by
371cc64c9 — **recoverable from git at `371cc64c9^:.agents/slop/jsfp8/drive.mjs`** …)"*. **THE
GATE'S OWN REFUSAL TEXT NAMES THE RECOVERY REF**, and the blob is there:
`git cat-file -t '371cc64c9^:.agents/slop/jsfp8/drive.mjs'` → `blob`, **3 438 B**, and the restored
file is **byte-identical** (`git hash-object checks/drive.mjs` =
`4b99887189ec87de85d8096c7f4cbabdcc1e288f` = `git rev-parse '371cc64c9^:.agents/slop/jsfp8/drive.mjs'`).

**⇒ AND THE TREE'S OWN RULE SAYS WHERE A GATE'S INPUTS LIVE.** `gates/gatekit.py`: *"A GATE'S
INPUTS LIVE BESIDE THE GATE. `.agents/slop/` is being pruned, and a prune took seven of nine driver
and oracle files out from under these gates — every one of them went red on 'no such file' rather
than on a value. **A gate whose inputs live somewhere the tree is clearing is a gate with a shelf
life.**"* `checks/drive.mjs` IS the gate's driver, and `checks/gate.py:202` runs it.

**⇒ AND IT IS NOT IN THE CORPUS'S `SUBSTRATE_INPUTS`** (`checks/differ.py:1673`:
`"checks/differ.py", "checks/devpin.py", "bin/bend", ".agents/slop/graphcmp.py", …`), so restoring
it **does not move `substrate_digest()`** and **does not invalidate the corpus run**.

**⇒ AND IT IS ALSO A FIX IN ITS OWN RIGHT**, independent of the plants: with the driver restored,
`checks/gate.py --quick` answers **rc 0** with `FIXED  present 5121/5121  MISMATCH 0` over the
LIVE `tinybendygrad/runtime/dtype.js` — i.e. **the fp8 DECODE gate this tree has been REFUSING
since `371cc64c9` now RUNS, and the port AGREES with CPython on all 5 121 rows.** MEASURED.

**⇒ AND THE TREE ALREADY AGREES IT IS MISSING.** `gates/js-lane-census.py:23` says *"`checks/gate.py`
was the fp8 DECODE gate for this file and it REFUSES today (exit 3: its driver `checks/drive.mjs`
was swept by 371cc64c9), so this coverage exists nowhere else in the tree."* — i.e. the gate that
covers the dtype seam is DEAD because of a missing file, and `oracles/` has no other fp8 decode
oracle.

**⇒ AND `checks/drive.mjs` IS NOT NAMED BY ANY OTHER GATE**, so nothing else changes shape.

### 2d. TWO BEHAVIOUR FIXES THAT ARE NOT PLANTS BUT WERE NEEDED TO MAKE ONE HONEST

**`checks/dup-census.py` — `--one` NO LONGER PUBLISHES THE POPULATION ARTIFACT.** (§1.) Without
it the plant overwrote a tracked 797,251-byte census with a one-lane one. **A plant must not
rewrite the tree it is planted in.**

**`checks/nl-gate-noguard.py` and `checks/gate.py` — AN ABSENT NAMED INPUT IS REFUSED, NOT A
TRACEBACK.** (§1.) Both gates crashed where they should have refused, and in
`nl-gate-noguard.py` the crash's exit (**1**) was **the same number as a disagreement**. Both
gates' own `refuse()` docstrings say why that is wrong.

---

## 3. THE INSTRUMENT'S OWN PLANT

`.venv/bin/python gates/gate-surface.py --plant green` → **`PLANTS: RED (12/14)`**, rc 1.

**⇒ THIS IS UNCHANGED BY MY WORK, AND IT IS PROVEN, NOT ASSERTED.** MEASURED by running the
instrument's plant against the **pristine HEAD versions** of all six of my gates (`git show
HEAD:<file>` into a scratch tree, with `checks/drive.mjs` absent): **`PLANTS: RED (12/14)` — the
SAME TWO FAILURES.** **⇒ AND THE TWO FAILURES ARE THE INSTRUMENT'S OWN, NOT ANY GATE'S:**

- **5c** — *"ZERO or TWO module-level unpacks in the vocabulary's owner is exit **2** REFUSED"* —
  observed `rc=3/3`. **The instrument's OWN `vocabulary()` EXITS 3, NOT 2** — `gates/gate-surface.py:221`
  says so in as many words: *"**EXIT 3, NOT 2: `2` IS NOT IN THIS FILE'S OWN VOCABULARY.** … So the
  tree carried TWO numbers for ONE meaning."* **⇒ THE PLANT'S EXPECTATION WAS NEVER UPDATED WHEN
  THE EXIT CHANGED. A STALE EXPECTATION IN THE INSTRUMENT.**
- **6a** — observed `counted=False`: the synthetic `#!/bin/sh` gate is not in the census's SHELL
  HALF, because `gates-pop.discover()` admits a file only when the **COMMIT TREE** carries it, and
  a synthetic tree has no commit.

**⇒ NEITHER IS IN MY SCOPE** (I was told not to edit `gates/gate-surface.py`), and **NEITHER IS
CAUSED BY ANY GATE I TOUCHED** — 5c and 6a are synthetic-tree assertions that never read a
declared gate's source.

**⇒ AND 12 OF THE 14 ASSERTIONS PASS**, including the ones that matter for this change: **1** (an
UNPLANTED verdict is RED and NAMED), **2** (every verdict planted is GREEN), **3a** (a gate that
declares NO GREEN is RED), **3b** (THE BLIND SPOT, asserted), **3c** (ZERO declaring gates is RED),
**4a/4b/4c** (the three classes), **5a/5b** (the exit-code vocabulary).

---

## 4. THE COUNTS, WITH THEIR DENOMINATORS

| measurement | before | after | how measured |
|---|---|---|---|
| verdicts declared | 70 | 70 | `II SURFACE:` line |
| reached by a declared plant | 45 | **64** | `II SURFACE:` line |
| **UNPLANTED** | **16** | **0** | `II SURFACE:` line |
| MISPLANT | 9 | 6 | `II SURFACE:` line |
| NO-GREEN | 0 | 0 | `II SURFACE:` line |
| `RED … UNPLANTED|MISPLANT` lines | 25 | 6 | grep over the census output |
| lines REMOVED by my change | — | **19** | set difference, before-vs-after |
| lines **ADDED** by my change | — | **0** | set difference, before-vs-after |
| **my six gates' UNPLANTED+MISPLANT** | **12** | **0** | per-gate rows |
| my six gates' class | 5× UNTAKEN + 1× FINDING | 5× FAILURE + 1× FINDING | `IV` class rows |
| `gates/gate-surface.py --plant green` | RED (12/14) | **RED (12/14)** | measured at pristine HEAD too |

**⇒ AND 9 OF THE 19 REMOVED LINES BELONG TO A CONCURRENT UNIT.** §0. **MY SIX ACCOUNT FOR 12.**
**⇒ AND THE COUNT MUST NOT RISE** — it did not, on either reading (16 → 0 tree-wide; 12 → 0 for my
six), and **no row went from `RESOLVES` to `UNPLANTED`/`MISPLANT`** — the added-lines set is
**EMPTY**.

---

## 5. WHAT THE CENSUS SHOWS ABOUT MY PLANTS *REACHING*, NOT MERELY BEING DECLARED

The instrument **EXECUTES** each plant and requires the observed rc to equal the declared one, so
"declared" and "reached" are the same column: the census prints `reached 0/1/2`, `reached 0/1/3`,
`reached 0/3` — **not** the declared lists. **⇒ THE CENSUS SHOWS THE PLANTS REACHED.**
MEASURED: `checks/dup-census.py  declared 0/3  reached 0/3`, `checks/env-precond.py  declared 0/1/2
reached 0/1/2`, `checks/gate.py  declared 0/1/3  reached 0/1/3`, `checks/hermetic-census.py
declared 0/3  reached 0/3`, `checks/nl-gate-noguard.py  declared 0/1/3  reached 0/1/3`,
`checks/nl-gate.py  declared 0/1/3  reached 0/1/3`.

**⇒ AND I ALSO RAN ALL 17 PLANTS STANDALONE**, one process each, and every one produced the
declared rc (table in §1). **THE TWO ARE INDEPENDENT MEASUREMENTS AND THEY AGREE.**

---

## 6. A DECLARED SURFACE THAT LOOKED WRONG

**⇒ `checks/env-precond.py` DECLARES `2: "REFUSED"`, AND `gates/gatekit.py` CALLS 3 `REFUSED`.**
`gatekit.py:83` is `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. This file's own docstring
says *"EXIT: 0 declared-and-recorded · 1 a declared value MOVED (FAIL) · **2 usage** · 3 REFUSED —
a required input is ABSENT"*, and its `refuse()` returns **3** while its `plant()` returns **2** for
an unknown kind. **⇒ THE DECLARED `2: "REFUSED"` NAMES THE USAGE CODE AS A REFUSAL.**
`gates/gate-surface.py`'s clause V reads this as an **UNOWNED** exit code (2 is not in
`gatekit.py`'s five) — and it is one of the tree's **4 UNOWNED** rows today.

**⇒ WHAT I DID: I LEFT IT EXACTLY AS IT IS AND NAMED IT.** The declaration is **not** narrowed to
make a count go down; `PLANTS[2] = ["--plant", "nonsense"]` is the argv that reaches the **2** the
declaration names, and it is the file's own usage exit — **so the declared code is REACHABLE and
PLANTED, and the disagreement with `gatekit.py` is named in the file's own declaration comment.**
**⇒ THIS IS A REAL FINDING AND IT IS NOT MINE TO SILENCE.** Two owners own the meaning of `2`
(`checks/dup-gate.py` and `checks/wallcheck.py` spell it `USAGE`; `checks/env-precond.py` and
`gates/gate-surface.py` spell it `REFUSED`).

**⇒ AND THE OTHER CLAUSE-V ROWS ON MY SIX GATES ARE THE SAME SUBJECT**, not UNPLANTED/MISPLANT:
`RENAMED 0 'OK'` (gatekit says `PASS`), `RENAMED 0 'AGREE'`, `RENAMED 1 'BROKEN'` (gatekit says
`FAIL`). **⇒ I DID NOT TOUCH ANY OF THEM.** They are the tree's own vocabulary question and
`gates/gatekit.py` owns the vocabulary.

**⇒ AND TWO MORE, IN THE SAME FAMILY, ON GATES I DID NOT TOUCH:**
`checks/dup-gate.py` (2 `USAGE`), `checks/wallcheck.py` (2 `USAGE`), `gates/gate-surface.py`
(2 `REFUSED`). **LEFT ALONE.**

**⇒ ONE MORE THING THAT LOOKED WRONG AND WAS NOT MINE:** `checks/env-precond.py --check` (the
DEFAULT mode, no plant) answers **rc 1** today, because the pin anchor
`'e.update(LC_ALL="C", DEV=dev)'` no longer matches the live
`.agents/slop/graphcmp.py:2264`, which reads `e.update(LC_ALL="C", DEV=dev, BEND_NO_TELEMETRY="1")`.
**⇒ THAT IS A REAL, TRACKED FINDING ABOUT A STALE PIN — AND IT IS NOT A PLANT**, so I did **not**
use it as one and did **not** touch `checks/differ.py` or `.agents/slop/graphcmp.py` (both are the
corpus's `SUBSTRATE_INPUTS`, and the latter is another unit's file). **REPORTED HERE INSTEAD.**

---

## 7. THE CONCURRENCY, AND WHY THE COUNTS ARE STATED THE WAY THEY ARE

**HEAD MOVED DURING THE MEASUREMENT: `b90b15999` → `ac4c8888a`** (one commit by another unit,
`the cites-census counted SCRATCH files' claims…`). **⇒ AND FIVE GATES THAT ARE NOT MINE WERE BEING
EDITED IN THE WORKING TREE AT THE SAME TIME** (`checks/dup-gate.py` +25/−4, `checks/norm_check.py`
+23/−6, `checks/oracle_f64.py` +57/−8, `gates/upstream-pow-dtype-gate.py` +41/−17,
`gates/upstream-promo-lattice-gate.py` +17/−3 — MEASURED by `git diff --stat HEAD -- <file>`).

**⇒ THAT IS WHY THE TREE-WIDE "16 → 0" IS NOT ALL MINE**, and why §0 attributes the rows
per-gate. **⇒ AND IT IS ALSO WHY A SINGLE BEFORE/AFTER PAIR CANNOT CREDIBLELY CLAIM A TREE-WIDE
MOVEMENT ON THIS TREE.** **MY SIX GATES' NUMBERS ARE THE CREDIBLE ONES**, because they are the six
files I changed and no other unit touched them.

**⇒ AND A SELF-CORRECTION WORTH RECORDING:** mid-measurement I copied the **pristine HEAD
versions** of my six gates over my edited ones to establish the instrument's baseline (§3) and
**OVERWROTE MY OWN EDITS**. They were re-applied from scratch and **re-verified by execution**
(all 17 plants, declared rc == observed rc) and by a fresh census (`64/70 reached, 0 unplanted`).
**⇒ THE LESSON IS THE TREE's OWN**: a file another unit may read is a shared path, and **A
SCRATCH TREE IS NOT A `git checkout`** — the two look identical and one destroys work.

---

## 8. WHAT I COULD NOT PLANT, AND WHY

**NOTHING IN MY SIX.** Every declared verdict of every one of the six is now reached by a declared
plant, and the census says so.

**⇒ BUT TWO THINGS IN THE TREE REMAIN, AND NEITHER IS MINE:**

1. **The instrument's own two plants (5c, 6a)** — §3. **5c** is a **stale expectation inside
   `gates/gate-surface.py`** (it expects exit 2; `vocabulary()` exits 3, and the file's own
   comment says the 3 was the deliberate change). **6a** is a synthetic-tree limitation in
   `gates-pop.discover()` (a synthetic tree has no commit tree, so no file is "carried"). **⇒ I WAS
   TOLD NOT TO EDIT `gates/gate-surface.py`, AND I DID NOT.** **⇒ 5c IS A ONE-WORD FIX IN THE
   INSTRUMENT** (`2` → `3` in the plant's expectation), and it is the instrument's own row to fix.

2. **The other unit's five gates** — §7. Their plants landed in the working tree during my
   measurement; **I did not commit their files.**

**⇒ AND I DID NOT PLANT `--plant red` FOR ANY OF MY SIX GATES**, because none of the six declares
a red that is a FINDING except `checks/env-precond.py` (which already has `RED_IS = "FINDING"` and
whose red is `1: "FAIL"`, now planted by `--plant moved-only`).
