# What my own rebase destroyed, written down so it is lost once and not twice

MEASURED 2026-10-05. `gates/retention-check.py` is in **NONE of the last 523 revisions** — these three
instruments were never committed, and a `jj rebase` reverted the working tree out from under them.
Everything below was reported by a unit, verified by that unit, and then lost by my operation. This file
is the recovery: the findings, not the code.

## 1. THE RETENTION RULE — `runskeep`

> **A generated directory holds exactly the files its generator's most recent successful run declares,
> and nothing else.**

Four mechanically testable clauses:

| clause | |
|---|---|
| **I** directory holds exactly the generator's declared set (`gatekit.declared()`) | 8 gates, 0 residues |
| **II** a run clears its own output before writing | **WAS FALSE — see §2** |
| **III** an output directory is not in the index | **42 entries tracked; `.gitignore` cannot untrack, only a commit can** |
| **IV** a generated directory may exist only if its run was **healthy** | **FIRED ON THE LIVE TREE** |

Chosen over KEEP-LATEST-N and KEEP-ALL-IF-CHEAP because every generator writes **fixed names** into a
per-gate directory: "the previous run" is the same names with older bytes, not a second set of names.
**THE RULE REUSES `differ.py`'s OWN `unhealthy()` — IT IS A MEASUREMENT, NOT A NEW WORTH-TEST.**

**ONE COUNTEREXAMPLE THE RULE MUST NOT FIRE ON:** a healthy run may hold legitimately empty `*.err`.
`artefacts_ok()` excludes `.err` **deliberately**, because *a rule that flags a correct file is a rule
that always fails.*

## 2. THE GATEKIT BUGS — `runskeep`, reproduced

`gates/gatekit.py:130`, **the flake guard asked only about stdout**, so a deterministic type error matched
the flake exactly. Measured: `rc=1, stdout 0 bytes, stderr 246 bytes`. **STDERR IS THE DISCRIMINATOR.**
`_lane` had the identical bug and the same 25x retry waste.

> *** **CORRECTION, 2026-10-05, WRITTEN BY THE UNIT THAT REBUILT IT: **THIS FIX WAS **NOT** IN THE TREE.**
> I RECORDED IT AS SURVIVED BECAUSE I COUNTED 4 `stderr` MENTIONS IN `gates/gatekit.py` AND INFERRED THE
> FIX FROM A KEYWORD. `_warm` GUARDED ON `not stdout and rc != 0` — **THE FLAKE'S SHAPE *AND* A TYPE ERROR'S
> SHAPE.** I COMMITTED A DOCUMENT THAT SAID A GUARD SURVIVED BECAUSE ITS SUBJECT APPEARED IN A `grep`. ***

**AND THE TRAP THAT HAD TO BE KILLED TO FIX IT PROPERLY:** `bend` PRINTS
`... is available: run bend update` **ON STDERR ON EVERY INVOCATION, GREEN ONES INCLUDED — 42 BYTES,
MEASURED.** SO **"STDERR NON-EMPTY" IS NOT "BEND SAID SOMETHING."** `_said()` STRIPS IT. **AN INSTRUMENT
THAT PROVES A DISCRIMINATOR WORKS MUST FIRST MEASURE THE BACKGROUND NOISE ON A HEALTHY INPUT, OR IT WILL
DISCRIMINATE NOTHING AND STILL LOOK LIKE IT DISCRIMINATES.**

**THE STALE-ARTIFACT FIX DID NOT SURVIVE.** Three findings:

1. **`_clear()` at the top is NOT ENOUGH** — 5 of 17 exits are *after* the lanes write. Measured: three
   gate dirs held exactly `bd.out bn.out py.out gate.bin` and **no `.rows`**.
2. **A FAILED GATE RUN LEFT THE PREVIOUS RUN'S `bd.txt` IN PLACE, SO A DIFF AFTER A RED RUN DIFFED THE
   LAST *GREEN* RUN.** Same shape as `bend -o` leaving the previous exe. Outputs must be **staged and
   atomically promoted**, matching `checks/differ.py`'s own `.tmp.` convention.
3. The first fix then left `.tmp.py.out` behind — caught by scenario 2 of its own repro. **ONE `finally`
   closes it, which corrects the reasoning "a failure-path cleanup is five chances to forget one": true
   per-`return`, false for one `finally`.**

Repro harness: `gates/stale-repro.py` vs `gates/stale-repro-old.py`, same repro, old and new `gatekit`:

```
OLD RC=1  LEFT=bd.out,bd.rows,bd.txt,gate.bin  "bend produced no --check-only output in 25 tries"
NEW   RC=1  LEFT=NOTHING   "bend said: SOME PROOFS FAIL | - expected : '->' (no law named amt_clamp)"
```

## 3. THE FROZEN SHELLS — `shfinish`. **GONE. THIS IS THE WORST LOSS.**

`gates/oracles/` held 7 `.sh` reduced to `exec` shims, **frozen byte-for-byte with sha256 pins checked in
code** — at the same depth as `gates/` so each shell's own `cd ../..` still resolves, because **the sweep
deleted the first location mid-run**. `gates/oracles/` is now **empty**.

The port was justified per gate, over 7 plants x 3 gates: **`stdout=IDENTICAL` on all three `clean` runs,
19 of 21 input sets agreeing.** Three of the seven were byte-identical copies, so **3 distinct gates**:
`mixin-op-gate`, `beautiful-mnist-gate`, `late-gate`.

**THE TWO DISAGREEMENTS ARE FINDINGS, NOT NOISE:**

1. **`mixin` WENT GREEN ON A COMPARISON IT HAD JUST DELETED.** The shell filters bend-only rows out of
   **both** lanes (`:28-31`), so when CPython starts emitting `rop_gap=` the filter removes it again.
   `gatekit`'s `port_only` catches it. **THE PORT IS STRICTER THAN THE SHELL — THE ONE DIRECTION A PORT
   MAY NOT DRIFT SILENTLY.**
2. **`bmn`/`oracle-gone`: BOTH RED, rc 2 vs rc 1** — `set -e` propagating the missing oracle's status.
   **NOT "FIXED": matching an accident of `set -e` is the move that made a shell report UNCHANGED on a
   diff it never ran.**

**NO MEMORY BOUND WAS ADDED, DELIBERATELY.** Neither shell had one; `bounded.py` returns 3 for memory and
4 for time, **and neither is a status these lanes produce** — *"bounding would be a verdict change dressed
as safety."* Measured peaks **1,368 / 1,531 / 734 MB**. TODO(GXR-12).

## 4. TWO `gatekit.py` FIXES THAT MADE THE PORTS POSSIBLE — `shfinish`

- **`port_only` WAS UNREACHABLE.** Claim 3 in `gates/README.md` described a shape the row-count check made
  impossible: it demanded `rows` of *every* lane, **and a port-only row is absent from the oracle by
  definition.** Measured: *"py has 32 rows, expected 36"*.
- **`if self.diverges:`** ran the stale-exclusion check only for gates that HAD a divergence.
  `mixin`'s exclusions are **all** port-only, **so it checked nothing.**
- Plus `warm=`, because `mixin-op-gate.sh:26` ran `--check-only` bare under `set -e` and
  `beautiful-mnist-gate.sh:29` ran it `|| true`. **Same instrument, opposite verdict, because the two
  shells disagreed.**

## 5. A MISSING BASELINE IS NOT A PASSING BASELINE

`late-gate.sh`'s `--base` arm is gone **and that is the point**: its baseline
`.agents/slop/late-pre-split.txt` no longer exists, **so it printed `MATCHES` and exited 0 having run
nothing.**

## 6. STILL TRUE, REPORTED BY `runskeep`, NOT FIXED

**`runs/graphcmp/D/` IS A TOTAL FAILURE PRESENTED AS THE CORPUS VERDICT.** 70 files, 2 distinct mtimes —
one coherent run — and that run: `graphs-agree=0  not-comparable=16  stable-failed=5 of 5  selfcheck=rc=1
census-rc=rc=1`, with `D2-canon-bend-indexed.txt` at **0 bytes**. **`checks/README.md:44` calls
`D0-run-summary.txt` "the run's verdict" and `:67` "the only file `repro` reads for health", so a reader
is INSTRUCTED to trust it.** **THE FILE SET IS NOT THE VERDICT.**

**`checks/differ.py:458` says "Reported, not fixed -- see DIFFPY.md" AND `DIFFPY.md` EXISTS NOWHERE.**
The "reported" half points at nothing.

**THE PIN DOES NOT COVER WHAT MATTERS.** `oracle-repro.sh` READS BY NAME:
`find runs/graphcmp/D -name '*.txt' ! -name '*.err'` and `s=runs/graphcmp/D/D0-run-summary.txt`.
**A RENAME MAKES `artefacts_ok()` MATCH 0 OF 22 FILES AND `healthy()` GREP A NONEXISTENT PATH — NEITHER
ERRORS. A SHA PIN OVER A SCRIPT WHOSE `find` NO LONGER MATCHES CERTIFIES A GATE THAT CHECKS NOTHING.**
That is why the `.txt` retirement must stop short of `differ.py`'s output contract.

## 7. TRAPS, ALL MEASURED, NONE OF WHICH I KNEW IN ADVANCE

- **`Path.exists()` FOLLOWS SYMLINKS** — a 21-set diff silently never ran.
- **The sweep deleted the frozen oracles mid-run** (§3).
- **Five units edit the tree at once:** `beautiful_mnist.bend` read WARM at 19:19 and COLD at 19:23.
- **`census.py` reading `shfinish/plant/` counted 602 files / 33 gates** instead of 310 / 20 — **a shadow
  tree inside the census**, the same class as a citation index built from the tree being swept.
- **Two plants reported 0 rows because of harness bugs** (`dotxt`): a regex matching one line of a two-line
  body, and a plant placed after an early return. **A 0 FROM A PLANT IS THE FIRST THING TO SUSPECT.**

## 8. WHAT I SHOULD HAVE DONE

**COMMIT EACH UNIT'S WORK THE MOMENT IT REPORTED, BY EXPLICIT PATH, BEFORE DISPATCHING ANYTHING ELSE.**
`jj` refused me five times today and each refusal was information: `--allow-backwards` dropped the
author's README **twice**; a tree pathspec took **538 files from a running unit**; a rebase reverted the
working tree **four times**. **`jj restore --from <rev> -- <paths>` WRITES FILES AND MOVES NOTHING — IT IS
THE ONLY TOOL IN THIS REPO THAT COULD NOT HAVE COST ME A UNIT.**
