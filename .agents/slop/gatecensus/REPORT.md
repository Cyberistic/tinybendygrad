# GATE CENSUS — REPORT

Measured 2026-10-05, 14:07–16:20. Artifact: `.agents/slop/gatecensus/run.log` (932 lines, the
durable one). Scripts: `enum.py` (count), `classify.py` (decide), `run.py` (execute), `group.py`
(attribute), `rebuild.py` (recover rows after a prune took the JSON).

## 1. THE DENOMINATOR

`.agents/slop` measured directly (`enum.py`), shadow trees excluded:

| | count |
|---|---|
| `.sh`/`.py` anywhere under `.agents/slop` | **5,802** |
| at slop top level | **721** (matches the brief's 719 to within the tree's own churn) |
| in subdirectories | 5,081 |
| **in a checked-out `tinygrad`** (6 of them: `differverdict/*`, `opstree`, `xd1/*`) | **4,624** |
| **POPULATION** — not a copy, not vendored | **1,172** |
| **gate-shaped BY NAME, outside shadow trees** | **455** — the denominator for this census |
| excluded UNSAFE by name (would write the port) | 17 |
| **ATTEMPTED, sequentially, both bounds** | **438** |

**719 top-level files are NOT 719 gates.** Of the top-level population my classifier returns
**354 GATE / 165 scratch / 147 one-shot** on the 666 that remain (the prune has taken 55 since
14:07). 312 of the 719 are named by nothing and say nothing in their name about deciding anything.

**A GATE IS NOT A GATE-SHAPED FILE.** The brief's 356 candidates collapse to **285 by subject with
235 singletons**, and my measurement agrees on the shape if not the exact instant.

## 2. THE CLASSIFIER — FOUR FIXES, EACH ONE MEASURED

`move_gates.py` over-cited. It is gone (the prune took `_cleanup/`); the corrected version is
`.agents/slop/gatecensus/classify.py`, with `--selftest` that fails if a fix does not move a number.

| defect | before | after |
|---|---|---|
| **1. git pathspec `*` crosses `/`** — 26 of `substrate-check.sh`'s 43 "citers" were inside `differverdict/root/`, **a copy of this tree inside this tree** | 43 / 39 / 21 / 22 | **17 / 12 / 6 / 6** with `:(glob)` |
| **2. bare basename**, no extension | `bend`: 89 hits | **0** — no extension to anchor on, so the instrument refuses to answer rather than answering about the *language* |
| **3. substring, not word token** | `.out`: 23 hits | **2**; `.err`: 6 → 9 |
| **4. a citation from a copy of this tree** | admitted | corpus asserted shadow-free (**0** shadow paths) |

**Defect 1 is the one that had to be found.** `git grep -- '.agents/slop/*.md'` is not a shell glob;
git's pathspec `*` matches `/`. Every count above is a whole-token Python match over an explicit,
asserted corpus — and the already-known failure (the anchored regex handed to `git grep -E`, POSIX
ERE has no lookaround, rc 128 swallowed as "no citations", **every gate named by nothing** and a
confident list printed on a total failure to look) is why the anchor is applied in Python.

**The brief's 16/11/5/5 are the same numbers at an earlier instant.** The tree moved: `checks/README.md`
was created 2026-10-05 02:23 and cites `graphcmp-run.sh` and `graphcmp-repro.sh`. I reproduce 16/11/5/5
exactly by scoping to top-level slop reports + `AGENTS.md` and excluding `checks/README.md`. The
difference is corpus growth, not a disagreement.

**WHAT I GOT WRONG IN MY OWN CLASSIFIER.** It called `bend_fix.py`, `bend_topo.py`, `bend_dedup.py`,
`afloat-patch.py` and `ag-order.py` gates — the exact failure the brief named. They are cited only by
`notes/bend2-constraints.md`, which documents instruments; **a citation that explains an instrument is
not a dependency on it.** My `ONCE` regex also matched `sweep`, which wrongly demoted nine real gates
(`arena-sweep.sh`, `dd-sweep.sh`, `ip_mutate.sh`, …). The concurrent `checks/sweep.py` got both right:
it requires `names_it` AND name-or-executable, and it promoted **0 of my 165 scratch**.

## 3. PASS / FAIL / NOT-RUN / SKIP, AGAINST THE DENOMINATOR

438 attempted, **sequentially, one live gate at a time**, each inside
`checks/bounded.py --seconds N --mb 1024`.

| | count |
|---|---|
| **PASS** | **112** / 455 |
| **FAIL** | **91** / 455 |
| **NOT-RUN** | **183** / 455 |
| **SKIP** | **14** + **38 reclassified** (see below) |
| UNSAFE, not attempted | 17 |
| **I COULD NOT RUN** | **252 of 455. Beside the 203 I could.** |

**NOT-RUN is 183 because it is honest, and 122 of those were never given their second chance:** pass 1
at 25s marked 184 rows unresolved, pass 2 re-ran them at 180s, and **the prune killed my process at
62 of 184**. Those 122 are reported as pass-1 saw them. `NOT-RUN` breaks down as: timeout, memory
kill, zero bytes, and rc 0 with no verdict token. **Both bounds fired and were caught**: `frombits/gate.sh`
hit **peak 1830 MB** against the 1024 MB ceiling — the guard working, and recorded as `NOT-RUN`, never
as a pass.

**38 FAIL rows were reclassified as SKIP after attribution.** All 38 die on
`IndexError` from `sys.argv[1]` with no argument — verified by hand on `ag-diff.py:9`. That is
"needs a file argument, run bare", the same class as a usage refusal, not a red.

### Three harness bugs that produced FALSE numbers, and their fixes

1. **`bounded.py` exit 3 is ambiguous.** `bounded.py:152` ends `return rc if rc else 0`, so a
   WITHIN-LIMITS run whose *child* exited 3 exits 3 — byte-identical to the KILLED-ON-MEMORY return
   at line 147. `substrate-check.sh` refuses an empty population with **exit 3 at peak-RSS 2 MB**.
   Reading the exit code calls a correct refusal a near-OOM. **The verdict token is now parsed; the
   exit code is recorded beside it, never substituted for it.**
2. **Classifying on the rc while capturing no text** gave 425 FAILs of which **404 could not name
   what they were failing on**. Every row now keeps the child's verbatim output and quotes the cause
   line — a traceback's last line, where the defect is named.
3. **A per-file shadow test cannot see a shadow tree**, because the marker (`.agents/`, `tinygrad/`)
   is a property of the *directory*. Pruning at the walk took the denominator **1,375 → 455**, all
   excess being copies.

**VERDICT VOCABULARY.** `arena-census.py` prints `SAFE 172  LATENT 1061  DEFECT 0` at rc 0 and was
recorded `NOT-RUN`, because no token covered it. A census whose only job is to tell a green from a
silence cannot afford a false negative; the census's own vocabulary is now in the pattern.

## 4. REDS GROUPED — 91 RED GATES ARE 46 DISTINCT PROBLEMS

**A COUNT OF RED GATES IS NOT A COUNT OF PROBLEMS.** 91 reds, mean 2.0 gates per problem.

| red gates | distinct problem |
|---|---|
| 16 | **one malformed file**: `debug-gate-out.0.py:73` — `ar_ring_L2=RING ALLREDUCE 4x300000 \| dtypes.f32` is not valid Python. Its 15 siblings (`debug-gate-out.1..7`, `debug-gate.0..3`, `.unset`) are **the same script at a different debug level** — one broken line, 16 reds |
| 16 | syntax errors across 3 unrelated scripts |
| 11 | **UNQUOTED** — the harness captured no text. Counted and flagged, never merged into a finding |
| 8 | import errors (`ops-oracle.py`, `validate-gate.py`, …) |
| 4 | `importlib` not defined — one missing import in 4 gates |
| 4 | missing file |
| the rest | ~1–2 each, incl. `KeyError: 'fp8e4m3'` (2), `dtypes.fp8e3m3` (2), `sel_registerName` (1) |

**THE LARGEST SINGLE CAUSE IS A PLATFORM ONE, NOT A PORT ONE.**
`RuntimeError: Attempting to relocate against an undefined symbol sel_registerName` —
a macOS Metal symbol absent from this host, raised in `tinygrad/runtime/support/elf.py:13`. It is one
line of environment, not a defect, and it is not mine to fix.

**Report the line, do not fix it.** `debug-gate-out.0.py:73` is one line in a file belonging to a
unit mid-edit; `elf.py:13` is upstream; both are reported, untouched.

## 5. DISTINCT GATES, DUPLICATES COLLAPSED

**438 gate-shaped files are 400 distinct gates.** Five byte-identical families, and one is enormous:

- **35× `ag-verify.sh`** — the same 3 KB script copied into 35 unit directories. **35 files, 1 gate.**
- 2× `debug-gate-out.0.py`, 2× `debug-gate-out/debug-gate.0.py`, 2× `x86/x86-oracle.py`, 2× `x86/x86-sweep.py`

Byte-identity only. Near-identical does **not** collapse — under-counting a suite is the mirror image
of over-counting it, and this project has paid for both.

## 6. MIGRATION ORDER

Load-bearing first, because a path that stops resolving turns a recorded claim into a dead reference.
Citer counts are live (the tree moved during the census).

**TIER 1 — the four the whole project leans on**
1. `substrate-check.sh` — **38 citers**
2. `e2e.sh` — **32 citers**
3. `graphcmp-run.sh` — **16** (already an `exec` shim onto `checks/differ.py`)
4. `graphcmp-repro.sh` — **16** (same)

**TIER 2 — per-family, alphabetical within the family** (the 338 remaining GATEs: `*-gate.sh`,
`*-oracle.py`, `*-census.py`, `*-sweep.sh`, …). Move each with an `exec` shim at the old path so all
existing invocations keep working.

**TIER 3 — the 16 whose name says they decide something and NO document names them.** They are
`[NAME ONLY]` in `classify.py --list`. A name is evidence about intent, not a measurement; they are
listed separately so the choice is visible rather than buried.

**TIER 4 — the 165 scratch and 147 one-shot. DO NOT MOVE.** `bend_fix.py`, `bend_topo.py`,
`bend_dedup.py`, `afloat-patch.py`, `ag-order.py`, `ag-fix1..13.py`. Named by nothing, deciding
nothing, already run once and answered in a report. Moving them is how `checks/` becomes a junk
drawer. **`checks/sweep.py` moved 0 of my 165 scratch — that agreement is the check on my classifier.**

## 7. WHAT ELSE I MEASURED, AND THE ONE WARNING

**A CONCURRENT SWEEP RAN THREE TIMES WHILE I MEASURED.** At 14:24 all 719 top-level slop files
disappeared; at 14:29 they were back. At 16:09 my entire `gatecensus/` directory was deleted —
including the uncommitted `results.json`. **I recovered the scripts and `run.log` from git
(`c11531564`); the JSON is rebuilt by `rebuild.py` from the log.** This is why the log is the artifact:
the transcript survived and the machine-readable convenience did not.

**Every number in this report was taken at a different instant of a tree that is being pruned under
me.** That is not a caveat to wave at — it is why each table carries its own denominator, and why
`rebuild.py` exists. **A GREEN ARTIFACT AND AN UNMEASURED GATE SUITE IS A PASS WITH THE LIGHTS OFF
IN THE ROOM IT IS SUPPOSED TO BE CHECKING.** This census is a partial measurement of a moving target:
203 of 455 gates ran, and I have reported every one of the other 252 as NOT-RUN, SKIP or UNSAFE.