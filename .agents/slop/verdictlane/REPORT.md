# THE `--verdict` LANE OVER THE PORT -- what was built, what was measured, and what it refuses.

**HEAD measured:** `8dde14ef7460f4cf9d5c9ef3d3aee23601bd428b` (`git rev-parse HEAD`,
read with `env -u GIT_INDEX_FILE`; the tree's index is ARMED and an armed index
answers a `git` question about the INDEX, not about the commit).
**Run at:** `2026-10-23T00:36:08Z` (`date -u`; the receipt in `kernel.json` carries
the same stamp, and the receipt names the HEAD beside it so a reader can tell
which tree a verdict came from).
**Machine:** 12 cores, `hw.memsize` 17,179,869,184 B (16 GiB).
**The gate:** `gates/verdict-lane-gate.py`. **The verdict:** `PASS`, exit `0`.
**The plant:** exit `0`, 7 of 7 cases as expected.

**THE HEAD MOVED FOUR TIMES UNDER THIS SESSION** -- `98b17949dd78a3a773c7e40ac079267739faaa28`
at 00:07 UTC, `d4160980e7734b7c2606c8fa31a8596f3f23c442` at 00:26 UTC,
`db98a9bfd364b360dcb90b654399dfba492bbdbd` at 00:32 UTC, and
`8dde14ef7460f4cf9d5c9ef3d3aee23601bd428b` at 00:34 UTC.  The repository is a
moving target; this report names the one it measured.

---

## 0. WHAT THIS LANE IS FOR

`checks/port-compile-gate.py` asks **"does the port compile?"** -- 165 of 169
files compile, 4 are cold by design -- and it asks `--check-only`, which is the
**unverified TypeScript checker**.  `references/bend/bend2/main.ts:816` asks a
**stronger** question: `--verdict` re-checks the same book against the
Lean-verified kernel (BendTT).  So the two lanes are not the same instrument,
their **agreement** is a claim worth making, and their **disagreement** is a
finding worth failing on.  This gate runs both over the port's proof family and
reports the agreement classes per file.

**MEASURED RESULT: all seven files AGREE, and three of them reached the kernel.**
There is no disagreement on this revision.  That is a result, not a gap -- and
the lane's value is that it can say so *about a pinned kernel* rather than about
whatever binary happened to be in `~/.bend/`.

---

## 1. THE FINDING THE LANE IS BUILT AGAINST

`references/bend/bend2/safe.ts`'s `kernel_bin()` (measured at `safe.ts:1608`,
clone at `0a57ca0d`; the same function was at `:1483` before the clone moved --
see §8) is, in effect:

```ts
const hash = sha256(LEAN_VERSION + "\0" + bendtt.lean)[:16];
const dir  = ~/.bend/bendtt/<hash>;
const bin  = dir/bendtt;
if (fs.existsSync(bin)) { return bin; }     // USED AS-IS, NEVER REBUILT, NEVER CHECKED
```

⇒ **the verdict is decided by a binary outside the repository**, and both
`references/` and `bin/bend` are `.gitignore`d (`.gitignore:2` and `.gitignore:5`),
so the kernel's *source* is outside it too.  The tree's own measurement
(`.agents/slop/verdict-hunt2/REPORT.md` §3 M11, 2026-10-22): with `HOME` pointed
at a temporary directory holding a two-line shell script where the kernel goes,
the verdict **flipped both ways** with nothing changed in the repository.

**THE FIX IS THE OVERRIDE THE COMPILER ALREADY HONOURS.**  `kernel_bin()` reads
`process.env.BENDTT` **first** and returns it unconditionally, so this gate:

1. **BUILDS** the kernel from `references/bend/bend2/bendtt.lean` into a
   directory **it owns** (never `~/.bend/`, never the repository),
2. **PINS** the binary's sha256 and the source's sha256, in CODE (a pin in a
   comment is a pin that cannot fail -- `gates/gatekit.py`'s `oracle_drift`),
3. **REFUSES (3)** if the binary it is about to execute is not the pinned one,
4. runs every lane with `BENDTT=` set to that absolute path.

---

## 2. THE BUILD -- THE COMMAND REPRODUCED

`safe.ts`'s `kernel_bin()` builds the kernel with exactly three commands, in the
build directory, with `cwd` set to it:

```sh
lean --version                                    # must be 4.34.0 (safe.ts pins LEAN_VERSION)
cp bendtt.lean <build-dir>/bendtt.lean
lean  -c bendtt.c bendtt.lean                     # Lean -> C
leanc -O3 -DNDEBUG bendtt.c -o bendtt             # C -> the kernel binary
```

The toolchain is resolved the way `kernel_bin()` resolves it:
`~/.elan/toolchains/leanprover--lean4---v4.34.0/bin/{lean,leanc}` if they are
there, else the ones on `PATH`.

### THE PINS, AS THEY ARE NOW

| what | value |
|---|---|
| `PIN_LEAN_VERSION` | `4.34.0` |
| `PIN_SRC_SHA256` (`bendtt.lean`) | `cc78aa9ff3491ff1b788797bdcab4cb98107dcb1730ed99834f6933b11d88335` (174,222 B) |
| `PIN_KERNEL_SHA256` (the binary) | `7e7a4899bfd6b793fae3253cfee1f297ae9239f0e858795985dab6a5e990905b` (3,307,264 B) |
| the compiler's own cache key for this source | `d0a46dc01e1b26d1` -- **ABSENT from `~/.bend/bendtt/`**, so the default path would REBUILD |

### THE BUILD'S TIME AND ITS PEAK RSS -- MEASURED, FOUR READINGS

The instrument is `/usr/bin/time -o <file> -l`, which writes the child's own
stdout and stderr through and the report to the file, so the tool's diagnostics
and the measurement stay separable.  **The build is the heaviest thing in this
tree** and the tree's rule is a SUM over concurrently-running children, so the
peak is a number the gate records rather than an estimate.

| reading | when (UTC) | revision | `lean -c` | `leanc -O3` | total |
|---|---|---|---|---|---|
| 1 | 2026-10-23 00:07 | previous (`b9f3e0253abffb11`) | 13.24 s / 1,044,955,136 B | 4.73 s / 261,373,952 B | 17.97 s |
| 2 | 2026-10-23 00:13 | current (`d0a46dc01e1b26d1`) | 14.54 s / 1,021,820,928 B | 5.14 s / 262,471,680 B | 19.68 s |
| 3 | 2026-10-23 00:21:09Z (the gate's own first build) | current | 16.653 s / 1,044,234,240 B | 4.965 s / 250,281,984 B | 21.618 s |
| 4 | 2026-10-23 00:25:5xZ (`--rebuild`) | current | 14.11 s / 1,058,111,488 B | 5.885 s / 232,210,432 B | 19.995 s |

Readings 3 and 4 are the gate's own receipt (`kernel.json`, `build_seconds` and
`build_peak_rss_bytes`); readings 1 and 2 were taken by hand with the same
instrument.  The revision column is §8's table: the clone moved at 00:10 UTC.

**⇒ `lean -c` IS THE HEAVY STEP: 13–17 s and about 1.0 GB of peak RSS** (996 MiB
– 1009 MiB), and that is the number the tree's "60 % of `hw.memsize`" sum-rule
has to be spent on.  `leanc` is 4.7–5.9 s and 221–250 MiB.  The whole build is
18–22 s and it is done **once**, because the gate keys its build directory by the
source's sha256 and reuses the binary after the pin check.

---

## 3. THE POPULATION -- DISCOVERED, NOT LISTED

`AGENTS.md` doctrine 1: "Never list in this file what an instrument discovers."
So the population is read out of the source, by a rule that is stated in the gate:

> a port `.bend` file is a **proof root** when **no other port `.bend` file
> imports it** AND its **transitive import closure contains a file that declares
> a law**; the population is the union of those closures.

Both halves are the port's own: the import edges are the files' `import` lines
(resolved the way bend2 resolves them -- relative to the *importing* file's own
directory), and a law is bend2's own `law` keyword
(`references/bend/bend2/bend.ts:50`) or a def whose type is a proof.

**MEASURED on this revision: TWO roots, SEVEN files.**

* root `tinybendygrad/LAWS/PROOF-ALL.bend` -- the aggregate the port itself calls
  "the aggregate gate" (`LAWS/PROOF-ALL.bend:1`).  Its closure is the six proof
  files.
* root `tinybendygrad/runtime/autogen/libclang.bend` -- the FFI file, which
  declares 335 `law`s of its own and is imported by nothing.  Its closure is
  itself.

The files that declare a law are **three**: `LAWS.bend` (34), `PROOF.bend` (19
proof-typed defs) and `runtime/autogen/libclang.bend` (335) -- the receipt names
all three under `law_files`.

**⇒ THE POPULATION IS SEVEN FILES: the six the brief names, plus `libclang.bend`.**
The seventh is in the population because the RULE puts it there, and it is a
useful row: it is the port's FOREIGN class, and it exercises the lane's
handling of a refusal that is not about TODOs.

---

## 4. THE PER-FILE TABLE, AND THE AGREEMENT CLASSES

`--check-only` is the unverified checker; `--verdict` is the verified one.  A
lane's answer is read from **stdout first** (`main.ts:820` writes `PASS` to fd 1
and `FAIL` to fd 2), and the compiler's own error classes are the classes.

```
tinybendygrad/LAWS/PROOF-ALL.bend            check=VERIFIED     verdict=VERIFIED     agreement=AGREE-VERIFIED     rc=0/0
tinybendygrad/LAWS/alu.bend                  check=VERIFIED     verdict=VERIFIED     agreement=AGREE-VERIFIED     rc=0/0
tinybendygrad/LAWS/spec.bend                 check=VERIFIED     verdict=VERIFIED     agreement=AGREE-VERIFIED     rc=0/0
tinybendygrad/LAWS.bend                      check=INCOMPLETE   verdict=INCOMPLETE   agreement=AGREE-INCOMPLETE   rc=1/1
tinybendygrad/PROOF.bend                     check=INCOMPLETE   verdict=INCOMPLETE   agreement=AGREE-INCOMPLETE   rc=1/1
tinybendygrad/PROOF2.bend                    check=INCOMPLETE   verdict=INCOMPLETE   agreement=AGREE-INCOMPLETE   rc=1/1
tinybendygrad/runtime/autogen/libclang.bend  check=FOREIGN      verdict=FOREIGN      agreement=AGREE-FOREIGN      rc=1/1
```

**THE CLASSES, AND WHAT EACH ONE IS:**

| class | meaning | count here |
|---|---|---|
| `AGREE-VERIFIED` | both lanes said `ALL PROOFS CHECK`; **the kernel was consulted and agreed** | **3** |
| `AGREE-INCOMPLETE` | both lanes said `Error: N TODOs found.` -- the port's proof DECLARES it is not a proof yet | **3** (`LAWS.bend` 34 TODOs, `PROOF.bend` 18, `PROOF2.bend` 16) |
| `AGREE-FOREIGN` | both lanes said `Error: N defs rely on unsafe or foreign code:` (`libclang.bend`, 336) | **1** |
| `DISAGREE` | the two lanes gave different answers | **0** |
| `MISMATCH` | the compiler itself said "this is a mismatch between the TypeScript implementation" -- the kernel rejected what the checker accepted | **0** |
| `NO-MEASUREMENT` | the lane ran and emitted nothing | **0** |

**⇒ ZERO FILES DISAGREE, on this revision, under the pinned kernel.**
The files that refuse do so under BOTH lanes and for the SAME reason, which is
the port's incompleteness and not a disagreement.

**WHAT IS *NOT* THE GATE'S FAILURE.**  A file that refuses under both lanes is
reported as `AGREE-INCOMPLETE` / `AGREE-FOREIGN` and does **not** turn the gate
red.  A gate that failed on the port's incompleteness would be red for a reason
that is not about the kernel, and would be red tomorrow for the same reason.

**LANE TIMINGS** (three runs of each of the fourteen lanes, the pinned kernel):
0.08 s – 0.17 s.  The FIRST run under a fresh HOME was 1.20 s, because `bun`
re-transpiles into the private HOME's cache.

---

## 5. THE PLANT, AND THE PROOF THAT IT GOES RED

`--plant` runs **seven cases on COPIES**; the working tree is never edited, and
nothing is written under `tinybendygrad/` (so the corpus's substrate digest,
`checks/differ.py`'s `SUBSTRATE_WALKS = ("tinybendygrad", "tinygrad")`, does not
move).  The rows are `plant.rows`; the transcript is `plant.out`.

| case | what it plants | want | got | measured |
|---|---|---|---|---|
| `CONTROL-REAL-TREE` | nothing: the gate on the tree as it stands | `PASS` | `PASS` | 7 files, 0 disagreements |
| `PLANT-TARGETED-KERNEL` | a treated kernel that fails **iff the elaboration mentions `powf`** | `FAIL` | `FAIL` | disagrees on exactly `{LAWS/alu.bend, LAWS/PROOF-ALL.bend}`; `LAWS/spec.bend` still `AGREE-VERIFIED` |
| `PLANT-BLANKET-KERNEL` | a treated kernel that fails everything | `FAIL` | `FAIL` | 3 of 7 files disagree -- the 3 that reach the kernel |
| `PLANT-PIN-MISMATCH` | the gate's own `check_pins` on the treated kernel | `REFUSED` | `REFUSED` | `01254cd7… != 7e7a4899…`. **It was NOT run.** |
| `PLANT-SILENT-COMPILER` | a compiler that exits 0 without writing a byte | `DEAD` | `DEAD` | "a lane ran and emitted nothing -- that is DEAD, not a FAIL" |
| `PLANT-HOME-POISON` | a treated kernel in the compiler's OWN cache dir + a poisoned `~/.bend/check.json`, under a private HOME | `PASS` | `PASS` | **the rows are byte-identical to the control** |
| `PLANT-COMMENT-CONTROL` | a comment-only copy of the proof family | `VERIFIED` | `VERIFIED` | judged exactly as the original is |

**⇒ THE GATE CAN GO RED, ON THE RIGHT THING.**  The targeted kernel is the
strongest of the seven: the marker `powf` lives in `LAWS/alu.bend` and in
nothing else, and the aggregate `LAWS/PROOF-ALL.bend` imports `alu.bend`, so
**exactly two files must disagree and `LAWS/spec.bend` must not** -- and the
plant asserts that SET, not just the verdict.  A blanket kernel would also
produce `FAIL`, so the verdict alone would not have proved localisation.

**THE TREATED KERNEL IS THE PRIOR HUNT'S EXPERIMENT, IN THE GATE'S OWN SHAPE.**
It is the two-line shell script of `.agents/slop/verdict-hunt2/REPORT.md` §3 M11,
at a path the gate hands to the compiler in `BENDTT`.  The prior hunt planted it
in `~/.bend/` and the verdict flipped; here it is planted in `BENDTT` and the
gate **notices**, because the pin does not match.

---

## 6. THE FIVE VERDICTS, AS EXITS (`gates/gatekit.py`)

| exit | word | when this gate produces it | MEASURED |
|---|---|---|---|
| **0** | `PASS` | every file got both lanes' answers, no file disagreed, **and at least one file reached the kernel** | the delivered run |
| **1** | `FAIL` | at least one file DISAGREED | `PLANT-TARGETED-KERNEL`, `PLANT-BLANKET-KERNEL` |
| **3** | `REFUSED` | a precondition was absent: no `bin/bend`; no `lean`/`leanc`; the kernel did not build; a pin did not match; the population is empty; or no file reached the kernel | `PLANT-PIN-MISMATCH`; and three live refusals, below |
| **4** | `SKIP` | **NOT PRODUCED BY THIS GATE.**  Named so the vocabulary is complete and a reader who sees 4 knows it came from elsewhere (`checks/e2e.py`). | -- |
| **5** | `DEAD` | a lane RAN and emitted NOTHING, after its retries | `PLANT-SILENT-COMPILER` |

**THE THREE LIVE REFUSALS, MEASURED** (the gate's own exit status, not its words):

| precondition absent | command | rc |
|---|---|---|
| no `lean`/`leanc` anywhere | `env PATH=/Users/cyberistic/.bun/bin:/usr/bin:/bin .venv/bin/python gates/verdict-lane-gate.py --toolchain-dir <empty> --kernel-dir <new>` | **3** |
| the kernel will not build | `.venv/bin/python gates/verdict-lane-gate.py --bend-dir <a dir whose bendtt.lean is not Lean> --kernel-dir <new>` | **3** |
| the kernel SOURCE moved (a copy of `bendtt.lean` with one comment appended) | `.venv/bin/python gates/verdict-lane-gate.py --bend-dir <that copy> --kernel-dir <new>` | **3** |

The third one's message, verbatim:

```
== REFUSED, NOT A VERDICT: verdict-lane-gate: the kernel source moved: bendtt.lean is
dcf183e59acc1098ee0669ce33fcb06c507fc11b5a095ccc6acde4ad30829f0c and the pin is
cc78aa9ff3491ff1b788797bdcab4cb98107dcb1730ed99834f6933b11d88335. The source lives in a
GITIGNORED clone (references/, .gitignore:2), so a pin is the only thing that names it.
Re-take the pins with --write-pins in the SAME commit.
```

**A GATE THAT MEASURED NOTHING MUST NOT EXIT 0.**  Three guards, all exercised:
* a population in which **no file reaches the kernel** is `REFUSED` (3), not
  `PASS` -- a green that measured nothing is not a green;
* a lane that emitted nothing is `DEAD` (5), not `PASS` and not `FAIL`;
* and the gate's OWN artifacts are removed **before any check can fail**, so a
  red run leaves no stale table of somebody else's green run.  MEASURED: the
  three live refusals above left their artifact directories holding **no `rows`
  file at all** -- only the receipt (`kernel.json`, with the `why`) and the
  captured exit status (`verdict.rc`), so a reader can see WHY it refused.

**AND A DEFECT THIS GATE HAD, FOUND BY RUNNING IT ON ITS OWN DELIVERABLE.**
`gates/gatekit.py`'s `_clear()` empties `gates/artifacts/<gate>/`, a directory the
gate owns outright.  This gate's artifact directory is CHOSEN BY `--artifacts`,
so it may not be the gate's alone -- and MEASURED 2026-10-23: a run with
`--artifacts .agents/slop/verdictlane` **DELETED THE REPORT THAT WAS SITTING
BESIDE THE ROWS**, because the clear removed every file in the directory.  A
clear that can delete a file the gate did not write is a clear that can delete
somebody's work.  **THE FIX: the clear removes ONLY THE THREE FILES THE GATE
WRITES** (`rows`, `kernel.json`, `verdict.rc`) and leaves everything else alone.
The stale-rows hazard the rule exists for is still closed, because `rows` is one
of the three.  MEASURED after the fix: a `canary.md` placed in the artifact
directory **survived** a gate run and a plant run.

---

## 7. WHAT WAS MADE INDEPENDENT OF THE REPOSITORY, AND HOW IT WAS MEASURED

The brief's last point: *the lane's own output must be a function of the
repository*.  Three things sat outside it, and each is cut by construction AND
by measurement.

### `~/.bend/bendtt/` -- the cached kernel

**CUT BY CONSTRUCTION.**  `BENDTT=` is set to the pinned kernel's **absolute
path**, and `kernel_bin()` returns it **before** it looks at the cache.  The
lane's `HOME` is a **private empty directory** the gate creates, so the cache
is not even visible to the child.

**MEASURED (`PLANT-HOME-POISON`).**  A treated kernel was planted at
`<private HOME>/.bend/bendtt/d0a46dc01e1b26d1/bendtt` -- the compiler's own cache
path for this source -- and the lane's rows were **byte-identical to the
control's**.  The verdict did not move by one byte.

**AND THE PRIOR HUNT'S EXPERIMENT, REPRODUCED HERE AS A CONTROL, WITH THE
VERDICT FLIPPING BOTH WAYS.**  A private HOME holding the treated kernel at the
compiler's own cache key for the CURRENT source:

```
$ HOME=<private> BEND_NO_TELEMETRY=1 ./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --verdict
SOME PROOFS FAIL
kernel exited 1 after SOME PROOFS FAIL
Sorry - this is a mismatch between the TypeScript implementation, and the formalized BendTT kernel. ...
rc=1

$ HOME=<private> BEND_NO_TELEMETRY=1 BENDTT=<the pinned kernel> ./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --verdict
ALL PROOFS CHECK
rc=0
```

**⇒ THE VERDICT IS DECIDED BY THE BINARY THE COMPILER IS POINTED AT, AND
`BENDTT` IS WHAT POINTS IT.**  Nothing in the repository changed between the two
runs: the difference is one environment variable, and it is the variable the
compiler reads FIRST.

(The first run also shows the compiler's own `MISMATCH` class, `main.ts:869`, in
the act: the compiler noticed that the kernel rejected what its type-checker
accepted.  That is the `MISMATCH` class in §4, and it is the shape a real
disagreement between the two lanes would take.)

### `~/.bend/check.json` -- the compiler's daily version check

**CUT BY CONSTRUCTION.**  `BEND_NO_TELEMETRY=1` skips the whole check
(`references/bend/bend2/main.ts:186-188`), and the lane's `HOME` is a private
empty directory, so the file is neither read nor written.

**MEASURED.**  `~/.bend/check.json` before a full gate run and after it:

```
before: 47 B  sha256 83a420d4a67e7103f5c9da00452f83a3c0d0a04d3e124cca85d8ba3b565a7d20  mtime 1792691577 (Oct 22 20:52:57)
after:  47 B  sha256 83a420d4a67e7103f5c9da00452f83a3c0d0a04d3e124cca85d8ba3b565a7d20  mtime 1792691577 (Oct 22 20:52:57)
```

**⇒ UNCHANGED IN BYTES AND IN MTIME.**  The lane did not phone home, and it did
not even read the cache.  (`PLANT-HOME-POISON` also plants a poisoned
`check.json` -- `{"ver": "99.99.99", "notice": "POISONED"}` -- under the private
HOME, and the rows are still identical.)

### `~/.elan` -- the Lean toolchain

**CUT BY CONSTRUCTION, AND THIS IS THE SUBTLE ONE.**  The toolchain cannot be
removed from the picture -- it is what compiles the kernel -- so it is not
hidden; it is **PINNED OUT**.  The toolchain reaches the verdict through
exactly one channel: the bytes of the binary it produces.  And those bytes are
pinned.  So:

* a **different Lean version** is REFUSED (3) before the build
  (`lean --version` must be `4.34.0`; the receipt records the version it used);
* a **different binary** from the same version is REFUSED (3) by the sha256
  check, before anything is executed;
* a **different size** is REFUSED (3) as well.

**⇒ THE TOOLCHAIN CANNOT SILENTLY CHANGE THE VERDICT.**  It can only produce a
binary that fails the pin.  The version is recorded in the receipt
(`lean_version: 4.34.0`) and in the build directory's own `build.json`, so a run
that built nothing still says which toolchain the pinned binary came from.

### the network

**CUT BY CONSTRUCTION.**  `BEND_NO_TELEMETRY=1` (the compiler's only telemetry,
`main.ts:179-212`) plus a private `HOME`.  The gate runs no command that
fetches anything: `lean`, `leanc` and `bend` are local, and `elan` is never
invoked (the toolchain binaries are used in place, so elan cannot try to
download one).

### ONE MORE THING, MEASURED

**THE REFERENCE CLONE IS NOT IN THE REPOSITORY, AND NEITHER IS THE COMPILER.**
`git ls-tree -r HEAD --name-only | grep -c '^references/'` = **0**, and the same
for `^bin/` = **0**.  `.gitignore:2` ignores `references/` and `.gitignore:5`
ignores `/bin/bend`.  ⇒ **THE PINS ARE THE ONLY THING THAT TIES THE VERDICT TO
A FIXED BODY OF TEXT.**  That is the whole reason this gate pins the binary
rather than merely building it.

---

## 8. THE MOVING TARGET: THE REFERENCE CLONE MOVED UNDER THIS SESSION

**THIS IS A MEASURED EVENT, NOT A HYPOTHETICAL, AND IT IS THE ARGUMENT FOR THE
PIN.**

| when (UTC) | `references/bend/bend2/bendtt.lean` | bytes | sha256 | the compiler's cache key | binary built from it |
|---|---|---|---|---|---|
| 00:07 | the previous revision | 172,753 | `83cdd36e66dcd2cabcc3d10556c9c874f8d823956feab88f8bb5a81473d51be3` | `b9f3e0253abffb11` | `989d9cf24677cd1549acec1714e5be1f0a23dd4690e3e885d750acf66d0a613b` (3,306,912 B) |
| 00:10 | **the clone became `0a57ca0d` ("Bend 2.0.38 (#1800)")** | 174,222 | `cc78aa9ff3491ff1b788797bdcab4cb98107dcb1730ed99834f6933b11d88335` | `d0a46dc01e1b26d1` | `7e7a4899bfd6b793fae3253cfee1f297ae9239f0e858795985dab6a5e990905b` (3,307,264 B) |

**THE BRIEF'S VALUES WERE VERIFIED, AND THEY ARE NOW THE PREVIOUS REVISION.**
At 00:07–00:08 UTC, before the clone moved, this session measured:

* `references/bend/bend2/bendtt.lean` sha256 = `83cdd36e…d51be3` ✔
* the cache key `sha256("4.34.0" + "\0" + bendtt.lean)[:16]` = `b9f3e0253abffb11` ✔
* the binary built from it with Lean 4.34.0 = `989d9cf2…a613b`, 3,306,912 bytes ✔
* and **`cmp` against `~/.bend/bendtt/b9f3e0253abffb11/bendtt` produced NO OUTPUT
  and rc 0** -- byte-identical ✔

**⇒ EVERY NUMBER THE BRIEF NAMED WAS CORRECT AT THE TIME IT NAMED THEM.**  And
**THREE MINUTES LATER THE PINNED SOURCE NO LONGER EXISTED**, because the
reference clone is a GITIGNORED working tree that another unit re-fetched.  The
gate's answer to that is the pin: the delivered gate pins the CURRENT revision,
and if the clone moves again the gate **REFUSES (3)** with

> `the kernel source moved: bendtt.lean is <sha> and the pin is <sha>. The source
> lives in a GITIGNORED clone (references/, .gitignore:2), so a pin is the only
> thing that names it. Re-take the pins with --write-pins in the SAME commit.`

**⇒ THIS IS THE FINDING, TURNED INTO A MECHANISM.**  A gate that merely BUILT
the kernel would have silently produced a different verdict three minutes later,
with no repository change to point at.  A gate that PINS the kernel says so.

**THE PINS MOVE WITH THE SOURCE, IN THE SAME COMMIT**, and
`--write-pins` prints the replacement constants:

```
$ .venv/bin/python gates/verdict-lane-gate.py --write-pins
PIN_LEAN_VERSION = 4.34.0
PIN_SRC_SHA256 = cc78aa9ff3491ff1b788797bdcab4cb98107dcb1730ed99834f6933b11d88335
PIN_KERNEL_SHA256 = 7e7a4899bfd6b793fae3253cfee1f297ae9239f0e858795985dab6a5e990905b
PIN_KERNEL_BYTES = 3307264
# the compiler's own cache key for this source: d0a46dc01e1b26d1
```

**THE HEAD MOVED TOO**, under this session: `98b17949dd78a3a773c7e40ac079267739faaa28`
at 00:07 UTC and `8dde14ef7460f4cf9d5c9ef3d3aee23601bd428b` at 00:34 UTC, with two
more in between.  The repository is a moving target and this report names the
one it measured.

---

## 9. WHAT THIS LANE DOES NOT CLAIM

* **IT IS NOT A COMPILE GATE.**  `checks/port-compile-gate.py` is the compile
  census; this one asks a different question of a different population.
* **IT DOES NOT CLAIM THE PORT'S PROOFS ARE COMPLETE.**  Three of the seven
  files declare `Error: N TODOs found.` and one declares 336 foreign defs.
  That is the port's state, reported as such.
* **IT DOES NOT CLAIM THE KERNEL IS UP TO DATE.**  It claims the kernel it ran
  is the pinned one, built from the pinned source with the pinned Lean.  Whether
  that kernel is the one upstream would build *today* is a different question,
  and §8 is the measurement of how fast that changes.
* **IT DID NOT COMMIT.**  No mutating git command was run; `git` was read only,
  and always with `env -u GIT_INDEX_FILE`.
* **IT DID NOT TOUCH THE TREE.**  The plant's scratch trees are in the system
  temp directory; nothing was written under `tinybendygrad/`; the only new paths
  are `gates/verdict-lane-gate.py` and `.agents/slop/verdictlane/`.

---

## 10. THE FILES

| path | what |
|---|---|
| `gates/verdict-lane-gate.py` | the gate |
| `.agents/slop/verdictlane/REPORT.md` | this |
| `.agents/slop/verdictlane/rows` | the per-file rows (`.rows`) |
| `.agents/slop/verdictlane/plant.rows` | the plant's rows (`.rows`) |
| `.agents/slop/verdictlane/lane.out` | the captured lane output (`.out`) |
| `.agents/slop/verdictlane/plant.out` | the captured plant transcript (`.out`) |
| `.agents/slop/verdictlane/kernel.json` | the receipt: pins, build timings, peaks, HEAD, timestamp (`.json`) |
| `.agents/slop/verdictlane/verdict.rc` | the captured exit status (`.rc`) |

**THE COMMANDS**

```sh
.venv/bin/python gates/verdict-lane-gate.py                    # the lanes, the classes, the verdict
.venv/bin/python gates/verdict-lane-gate.py --plant            # the plant, the control, the wrong shapes
.venv/bin/python gates/verdict-lane-gate.py --write-pins       # the pins for the source as it stands
```

**THE DEFAULT ARTIFACT DIRECTORY IS `gates/artifacts/verdict-lane/`** (the tree's
convention, and `.gitignore`d).  The delivered copy was made with
`--artifacts .agents/slop/verdictlane`, because `gates/artifacts/` is swept.

**NOTE THE ORDER, WHEN POINTING `--artifacts` AT A DIRECTORY THAT HOLDS MORE
THAN THE GATE'S OWN FILES:** the gate removes only `rows`, `kernel.json` and
`verdict.rc`, so a report beside them survives -- but the report is written
LAST, after the runs, because the first version of this file was deleted by its
own gate before it was written down.
