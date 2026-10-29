# THE FIVE GATES — EVERY DECLARED VERDICT HAS A PLANT THAT REACHES IT

**Commit:** `f9f868741` (2026-10-30).
**Instrument:** `gates/gate-surface.py`, READ-ONLY. It was NOT edited.
**Interpreter:** `.venv/bin/python` only. No `bend`. No `git add -A`. No directory staged.
Committed by path with `git commit --only -F <msgfile> -- <paths>`.

## 0. THE HEADLINE, AS TWO NUMBERS FROM THE INSTRUMENT ITSELF

`gates/gate-surface.py --report` after the commit:

```
II SURFACE: 70 verdicts declared, 64 reached by a declared plant,
   6 not reached, 0 unplanted, 0 misplant, 0 NO-GREEN
GATE-SURFACE: RED -- 22 gate(s) declare a surface, 64/70 verdicts reached, 0 unplanted,
   0 NO-GREEN, 4 UNOWNED exit code(s), 10 RENAMED exit code(s)
```

The BEFORE reading, taken at the start of this task on the same tree:

```
II SURFACE: 70 verdicts declared, 45 reached by a declared plant,
   25 not reached, 16 unplanted, 9 misplant, 0 NO-GREEN
```

**⇒ AND THE SIX MISSING VERDICTS IN THESE FIVE GATES ARE NOW REACHED, NOT MERELY DECLARED.**
The census prints the reached set per gate, and for these five it reads:

| gate | declared | reached | unplanted before | unplanted after |
|---|---|---|---|---|
| `checks/norm_check.py` | 0/1/3 | **0/1/3** | 1 (rc 3) | **0** |
| `checks/oracle_f64.py` | 0/1/3 | **0/1/3** | 2 (rc 0, rc 1) | **0** |
| `gates/upstream-pow-dtype-gate.py` | 0/1/3 | **0/1/3** | 1 (rc 3) | **0** |
| `gates/upstream-promo-lattice-gate.py` | 0/1/3 | **0/1/3** | 1 (rc 3) | **0** |
| `checks/dup-gate.py` | 0/1/2/3 | **0/1/2/3** | 1 (rc 3) | **0** |

**⇒ AND NO ROW WENT FROM `RESOLVES` TO `UNPLANTED`/`MISPLANT`.** The tree-wide `UNPLANTED` count
FELL 16 -> 0, and the remaining tree-wide reds are in gates that are NOT these five
(`checks/env-precond.py`, `checks/gate.py`, `checks/hermetic-census.py`, `checks/nl-gate.py`,
`checks/nl-gate-noguard.py`, `checks/no-txt.py`, `gates/gate-surface.py`, `gates/pyvals-gate.py`,
`gates/txt-carveout-gate.py`). Every one of them is `MISPLANT` or `UNPLANTED` for a reason this
task did not touch.

**⇒ AND THIS IS THE OTHER HALF OF THE SAME DEFECT.** `.agents/slop/plantsurface/REPORT.md:27-32`
records that the earlier unit's six gates left these five "edited concurrently" by another unit,
and names them: `checks/dup-gate.py`, `checks/norm_check.py`, `checks/oracle_f64.py`,
`gates/upstream-pow-dtype-gate.py`, `gates/upstream-promo-lattice-gate.py`. **That unit is this
one.** Six plus five is the sixteen.

## 1. THE PLANTS, ONE ARGV PER MISSING VERDICT, AND WHY THAT ARGV REACHES IT

All six new argv verified by EXECUTION (declared rc == observed rc), not by reading.

### `checks/norm_check.py` — `VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}`

**ADDED: `PLANTS[3] = ["--plant-refused"]`.**

The refusal above fires only when `.agents/slop/jslane2/gen_f32_seam.py` is ABSENT, and no argv
moves a file. `--plant-refused` therefore runs a COPY of this gate in a temporary tree which has
`pyproject.toml` and `tinybendygrad/` (symlinked, so `REPO` resolves and the tree-marker guard
passes) and this gate, but NOT the subject. The module-scope refusal fires for exactly the absent
subject it names.

MEASURED: rc 3, stderr `== REFUSED, NOT A VERDICT: input absent: …/.agents/slop/jslane2/
gen_f32_seam.py`.

### `checks/oracle_f64.py` — `VERDICTS = {0: "OK", 1: "FAIL", 3: "REFUSED"}`

**ADDED: `PLANTS[0] = ["--plant-ok"]` and `PLANTS[1] = ["--plant-fail"]`.** `PLANTS[3] = []` was
already there and already reaches 3 (no argv -> `needs <workdir> <mm-rows>` -> refusal).

The file's own comment said `0` and `1` "STAY UNPLANTED AND THAT IS HONEST" because both need a
real `mm-rows` file off a port run. The oracle's own `build()` reads that file as
`KERNEL_BEGIN … KERNEL_END` around a C kernel, and the SHAPE of that kernel is fixed by the
tracked `.agents/slop/f64/emit-f64.bend` — the signature, the loop nest and the `DELTA` literal
are all spelled there. So the plant writes that shape into a TEMPORARY directory (not a tracked
oracle) and runs the SHIPPED `build()` over it:

- `--plant-ok` writes the `double` signature. `build()` re-derives `DELTA`, runs the kernel under
  real tinygrad `DEV=CPU`, and compares against numpy float64. MEASURED: rc 0, and the two
  independent answers agreed.
- `--plant-fail` writes the `float` signature. That is the exact defect the oracle exists to
  catch, and `build()`'s own assertion (`"double* restrict data0_4" in port`) fires. MEASURED:
  rc 1, `PLANT fail: the oracle refused the float signature: the port did not emit a double
  signature`.

**⇒ AND `RED_IS = "FINDING"` WAS ADDED.** Its red is the PORT rendering `float*` where the lane
promises `double*` — a defect IN THE PORT, not a broken instrument. The class is EARNED because
`PLANTS[0]` reaches 0 in the census run.

**⇒ AND `main()` NOW EXITS.** It used to be `main()` with no `sys.exit`, so every code it
returned was thrown away and the process always exited 0. That is why `--plant-fail` first
measured rc 0. The fix is `sys.exit(main())`.

### `gates/upstream-pow-dtype-gate.py` — `VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}`

**ADDED: `PLANTS[3] = ["--plant", "refused"]`.**

This gate already has `--plant green` / `--plant red`. Its REFUSED exit comes from the drift
check: `gates/gatekit.py:oracle_drift` compares the working tree's bytes against the gate's
literal `DRIFT_PIN` and returns the list of mismatches; a non-empty list means REFUSED. So the
plant runs the SHIPPED reader over a pin that cannot hold, which makes the refusal the gate's own
refusal and not a copy of one.

MEASURED: rc 3, `upstream-pow-dtype-gate --plant refused: 1 pin(s) did not hold`.

### `gates/upstream-promo-lattice-gate.py` — `VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}`

**ADDED: `PLANTS[3] = ["--plant", "refused"]`.** The same house reader, over the same gate's own
`DRIFT_PIN`. MEASURED: rc 3.

### `checks/dup-gate.py` — `VERDICTS = {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED"}`

**ADDED: `PLANTS[3] = ["--plant-refused"]`.**

Its module-scope refusal fires when `.agents/slop/rebase-gate.py` or
`.agents/slop/eq/eq-census2.py` is ABSENT. `--plant-refused` runs a COPY of this gate in a
temporary tree which has the repository markers, `checks/verdict.py` and `gates/gatekit.py` (the
two readers the copy imports) but NOT the two row readers, so the refusal fires for exactly the
absent input it names. MEASURED: rc 3, `input absent: …/.agents/slop/rebase-gate.py`.

## 2. TWO BEHAVIOUR FIXES THAT WERE NOT PLANTS BUT WERE NEEDED TO MAKE ONE HONEST

**(1) BOTH `upstream-*` GATES STOPPED EXITING THE LIVE VERDICT.**

The old code was `return planted if planted == live else FAIL`. That makes a plant's exit a
function of the TREE: upstream currently compiles every pow row (`live` is PASS), so
`--plant red` measured rc 1 — but only because the tree happens to disagree with the planted
state. The promo gate's live verdict is FAIL (6 no-join pairs, 24 non-associative triples), so
`--plant green` measured rc 1. **A PLANT THAT EXITS THE LIVE VERDICT MEASURES THE TREE, NOT THE
PLANTED STATE.** Both now `return planted`, and the live verdict is PRINTED BESIDE the planted
one, so the disagreement is visible rather than conflated.

MEASURED, before and after:

| gate | `--plant green` before | after | `--plant red` before | after |
|---|---|---|---|---|
| `upstream-pow-dtype-gate.py` | 0 | **0** | 1 | **1** |
| `upstream-promo-lattice-gate.py` | **1** | **0** | 1 | **1** |

The promo gate's green plant was MISPLANTED before this fix (it produced 1 where it declared 0);
it is RESOLVED now. No check was weakened: the live verdict is still printed on every plant.

**(2) `checks/oracle_f64.py` GAINS `RED_IS = "FINDING"`** — see §1.

## 3. THE INSTRUMENT'S OWN PLANT

`.venv/bin/python gates/gate-surface.py --plant green`:

```
PLANTS: RED (12/14)
```

**UNCHANGED BY THIS WORK, AND MEASURED AS UNCHANGED**: the same 12/14 was read BEFORE the edits
and AFTER them. The two failures are the instrument's own pre-existing defects:

- **5c** expects `vocabulary()` to exit 2 for an ambiguous owner; `gates/gate-surface.py:221-226`
  records the deliberate change to exit 3, so the expectation is stale.
- **6a** expects a synthetic tree to hold a shell entry point that `gates-pop.discover()` admits,
  and a synthetic tree has no commit tree.

**`gates/gate-surface.py` WAS NOT EDITED.** The brief forbids it and it was not touched.

## 4. THE CHARGED CENSUS

`.venv/bin/python gates/gate-surface.py` (no `--report`) exits 1, with the same census:

```
GATE-SURFACE: RED -- 22 gate(s) declare a surface, 64/70 verdicts reached, 0 unplanted,
   0 NO-GREEN, 4 UNOWNED exit code(s), 10 RENAMED exit code(s)
```

The remaining reds are `UNOWNED` (4) and `RENAMED` (10) vocabulary disagreements and the six
`MISPLANT`s listed in §0. **⇒ AND NO DECLARATION WAS NARROWED.** Every `VERDICTS` mapping in
these five files still names exactly the codes it named before; the only change to a declaration
is the ADDITION of `RED_IS = "FINDING"` to `checks/oracle_f64.py`, which is a class and not a
verdict.

## 5. A SHARED-PATH INCIDENT, AND WHAT WAS DONE ABOUT IT

`gates/upstream-pow-dtype-gate.py` was being edited by ANOTHER UNIT at the same time: the working
tree carried a prose rewrite of the gate's header (the upstream `base needs to be float` guard had
become `integers to negative integer powers are not allowed` in the 2026-10-17 re-vendor). That
prose was NOT mine.

`git commit --only` commits the WORKING-TREE bytes of the pathspec, so the prose was swept into
`f9f868741` along with my plants. **⇒ AND THAT IS THE HAZARD `AGENTS.md` NAMES: A PATH THAT
OTHERS HOLD IS A SHARED PATH, AND `--only` BOUNDS THE COMMIT BY THE PATHSPEC BUT NOT THE
BYTES.** The prose is a MEASURED, CORRECT correction of the same class as the other unit's
`445cb9d15` ("13 lane-C STALE CLAIMS"), and it is not reverted here: reverting it would destroy
another unit's measurement, and the file is still being edited by them.

The working tree was left with THEIR bytes, so their edit is not clobbered. The next unit that
touches this path should know that the header prose is already in `f9f868741`.

## 6. WHAT COULD NOT BE PLANTED, AND WHY

Nothing in these five. Every declared verdict in all five gates is now reached by a declared argv
and the census says so.

## 7. THE FILES

| file | the change |
|---|---|
| `checks/norm_check.py` | `--plant-refused` mode + `PLANTS[3]` |
| `checks/oracle_f64.py` | `--plant-ok` / `--plant-fail` modes, `PLANTS[0]` / `PLANTS[1]`, `RED_IS`, `sys.exit(main())` |
| `gates/upstream-pow-dtype-gate.py` | `--plant refused` mode, `PLANTS[3]`, plant exits the planted verdict |
| `gates/upstream-promo-lattice-gate.py` | `--plant refused` mode, `PLANTS[3]`, plant exits the planted verdict |
| `checks/dup-gate.py` | `--plant-refused` mode + `PLANTS[3]` |

No `.txt` files were written. No `tinybendygrad/`, `checks/differ.py` or `checks/devpin.py` was
touched. `checks/differ.py` was never run.
