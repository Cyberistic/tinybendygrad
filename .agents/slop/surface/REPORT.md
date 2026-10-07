# GATE-SURFACE — the verdict surface of every gate, as a number every run

`gates/gate-surface.py`, landed 2026-10-07T03:00Z, `git rev-parse --short HEAD` = `95d24b73b`.
Owned and touched: `gates/gate-surface.py` (new), the `VERDICTS`/`PLANTS` exports on **13**
`checks/*.py` gates, and `.agents/slop/surface/`. No `bend` was started, nothing was committed,
`git add` was never run, and `AGENTS.md` / `tinybendygrad/` / any `gates/*.py` gate BODY were not
edited. Artifacts: `report.out` (the census), `check.out` (the same census, rc charged), `plant.out`
(the self-test).

This builds the instrument `coindependent` proposed and deliberately did not build
(`.agents/slop/coindependent/REPORT.md` §6). Its measurement is the reason:
**107 distinct exit codes declared, 28 reached, 79 (74%) never observed to fire, 40 entry points
presented in no state, 9 gates whose real surface is ZERO.** That was a session's finding from a
source SHAPE scan. This is the same number from a DECLARATION, re-derived every run.

---

## 1. HOW TO RUN IT, AND THE THREE EXITS

    .venv/bin/python gates/gate-surface.py            # census AND the check (rc charged)
    .venv/bin/python gates/gate-surface.py --report   # census only; rc never charged
    .venv/bin/python gates/gate-surface.py --plant    # the two-state self-test, synthetic only

Each gate may now export, at module scope:

    VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}          # exit code -> the token it prints
    PLANTS   = {0: ["--plant"], 3: ["--disarm", "DELETE"]}   # exit code -> argv that REACHES it

The instrument reads those two constants with `ast.literal_eval` off the **module body** and never
by import — importing a gate RUNS it (`gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py`
`sys.exit(2)` at module scope; every `gatekit.Gate` clears its own output directory in its
constructor). **Reading the constant the author wrote is reading a DECLARATION; scanning for
`return 1` is reading a shape.** Then it EXECUTES each plant and requires the observed rc to be the
declared one, because a declaration cannot audit itself (`gates/gates-pop.py`'s own lesson).

Exit **0** green · **1** red (a declared verdict has no plant, a plant missed its verdict, a gate
declares no green, or zero gates declare) · **2** REFUSED (empty population, or the root markers are
absent). `--report` always returns 0.

**`check.out` at rest is RED — and that is the correct current verdict, not a defect to hide.** 30
of 39 declared verdicts have no plant. The number is the deliverable.

---

## 2. THE POPULATION — reusing `discover()`, and what that does and does not settle

The population is **`gates/gates-pop.py:discover()`**, loaded BY PATH — the same one-module,
N-consumers shape `gates/gendirs.py` gave the generated directories. There is no second list.

`coindependent` measured **113** by its own recursive `os.walk` against **111** from `gates-pop`.
What actually happened, measured today:

| witness | count | what it is |
|---|---|---|
| `gates/gates-pop.ledger.tsv` | **111** rows | the **snapshot** written by the last `gates-pop` run |
| `gates-pop.discover()` live | **114** entries today (113 when this unit began) | a MEASUREMENT |
| `coindependent`'s `os.walk` | **113** | a measurement, recursive |
| this instrument, reusing `discover()` | **114** | the same measurement as `gates-pop` |

So the "111" was a **LEDGER row count**, and `discover()` reads **113→114** live. Reusing
`discover()` makes this instrument and `gates-pop` agree **by construction**, and the
113-vs-111 standing difference is gone **today** — but only because the tree moved, not because the
reuse settled anything. The instrument prints a **labelled control** (a recursive `os.walk`, never
used to decide membership) beside the population, and it names the 2 files the two universes
disagree about:

    gates/oracles/beautiful-mnist-oracle.sh
    gates/oracles/mixin-op-oracle.sh

**These are the finding.** `discover()` is `iterdir`-based, so it is structurally **blind to a
subdirectory of a gate home** — exactly the class `AGENTS.md` doctrine 1 catalogues. A shared
population is not a correct population; it is one that two consumers can no longer disagree about,
which is necessary and not sufficient. The control is what keeps the blind spot a printed line
rather than a silent one.

---

## 3. THE TRANCHE — 13 declared, 101 to touch, chosen by the measurement

**13 of 114 entry points declare `VERDICTS`. 101 do not.** The diff is small and bisectable on
purpose (`bendwire`'s lesson: land three sites, not thirty-seven). The tranche was picked by
**what the measurement says is worth covering**, not by ease — the 9 zero-surface gates and the
reachable gates with real two-state plants:

| class (from `coindependent`) | gates declared | plant? |
|---|---|---|
| REFUSED-only (real surface ZERO) | `checks/gate.py`, `checks/nl-gate-noguard.py`, `checks/norm_check.py`, `checks/oracle_f64.py` | `nl-gate-noguard`/`norm_check` only |
| swept input (green unreachable) | `checks/hermetic-census.py`, `checks/dup-census.py`, `checks/dup-gate.py`, `checks/rn-gate.py`, `checks/nl-gate.py` | none |
| two-state plants that reach BOTH | `checks/residue.py`, `checks/env-precond.py`, `checks/wallcheck.py`, `checks/no-txt.py` | yes |

Every one is `checks/*.py` (all 9 zero-surface gates are), so the tranche is inside this unit's
ownership. **The 40 `needs bend` entry points are NOT in the tranche and are named as the backlog**
(§6): declaring them needs a plant that runs `bend`, which this instrument deliberately does not do.

---

## 4. THE RULE, AND THE PLANTS THAT PROVE IT (`plant.out`, 5/5 GREEN)

**A declared verdict with no plant is RED, NAMED.** Three reds, each with its own denominator:

- `UNPLANTED <rc> '<token>'` — declared, no plant. *"A check nobody has ever seen fire is a check of
  unknown value."*
- `MISPLANT <rc> '<token>'` — a plant ran and produced a different rc (0 today).
- `NO-GREEN` — the gate declares no rc 0, so it can never report agreement: real surface ZERO.

`--plant` asserts five directions on synthetic trees, **never the live one**:

    1: an UNPLANTED verdict is RED and the verdict is NAMED            PASS
    2: every verdict planted is GREEN                                  PASS
    3a: a gate that declares NO GREEN is RED (real surface ZERO)       PASS
    3b: THE BLIND SPOT — a plant that exits 0 having read NOTHING
        is PASSED. This file cannot tell green-correct from
        green-vacuous without a per-gate input assertion.              PASS (the limit, asserted)
    3c: ZERO declaring gates is RED, never a vacuous green             PASS

Plant 1 asserts the **WORD** in the transcript (`UNPLANTED 1`, `FAIL`, `REFUSED`), not just `rc==1`,
because a checker that reds on everything would otherwise satisfy it. Plant 3b is the direction this
instrument is honest about being unable to reach (§5).

---

## 5. CAN IT TELL "GREEN BECAUSE CORRECT" from "GREEN BECAUSE IT MEASURED NOTHING"? — **NO, and that is reported as its own plant**

`checks/citation-gate.py` stayed green against a root that does not exist. This instrument **cannot**
distinguish that from a correct green: a plant that exits 0 after reading nothing is indistinguishable
from one that agreed, from the exit status alone. Plant 3b **asserts the limit** rather than promising
a discrimination that is not there.

The shape that WOULD close it, **reported and not built** (a second mechanism for this would be the
defect): each `PLANTS[rc]` entry must also name **the input it read**, and the instrument fails the
plant if the gate ran without that input. That is one declaration per plant, gated by the same AST
reader — not a new instrument. It is deliberately out of this tranche so that the ceiling below is a
real number rather than an aspiration.

The instrument's OTHER anti-vacuity guards are real and at the instrument level, not the plant
level: an **empty population is REFUSED (2)**, and **zero declaring gates is RED** — a run that
declares nothing has measured the surface of nothing and cannot be green.

---

## 6. THE HONEST CEILING — the number goes DOWN as the instrument gets more honest

Over the 13 declared gates: **39 verdicts declared, 9 reached by a declared plant, 30 unplanted,
0 misplant, 0 NO-GREEN.**

**9 of `coindependent`'s 28 REACHED verdicts are now kept reached on EVERY run**, with the exact
plant named:

| gate | reached | plant |
|---|---|---|
| `checks/residue.py` | 0, 3 | `--plant` / `--disarm DELETE` |
| `checks/env-precond.py` | 0, 2 | `--plant satisfied` / `--plant nonsense` |
| `checks/wallcheck.py` | 0, 4 | `--selftest` / `NO-SUCH-ID` |
| `checks/no-txt.py` | 0 | at rest |
| `checks/norm_check.py` | 0 | at rest |
| `checks/nl-gate-noguard.py` | 3 | at rest (refuses on the swept oracle) |

**The fraction moves the WRONG WAY as the instrument gets MORE honest, and that is the point.**
Declaring a gate's full exit vocabulary necessarily declares the codes nobody has ever planted:
`wallcheck` declares 6 and reaches 2; `dup-gate` declares 4 and reaches 0. A gate declared with only
its reached codes would read `9/9`; the honest declaration reads `9/39`. **An instrument that reports
a worse number as it gets more honest is doing its job; this one is reporting 26% reached today, down
from the vacuous 100% that a reached-only declaration would print.** The size of the backlog is
visible: **101 entry points declare nothing at all.**

**7 of the 13 declared gates currently cannot demonstrate green** (`UNPLANTED 0`): `dup-census`,
`dup-gate`, `gate.py`, `hermetic-census`, `nl-gate`, `oracle_f64`, `rn-gate`. That is the
zero-surface finding, expressed as a per-run number instead of a session's prose — and it has already
MOVED once since `coindependent`: `checks/norm_check.py` **exits 0 at rest today** (its input is
back), so it is no longer zero-surface. **The membership of the zero-surface set is live, which is the
argument for measuring it every run rather than writing it down once.**

---

## 7. WHAT THIS INSTRUMENT CANNOT MEASURE, NAMED

- **The 40 `needs bend` entry points** (all of `gates/*-gate.py` and `checks/substrate.py`, `e2e.py`,
  `sb-gate.sh`, …). Their `gatekit` surface is `0/1/3/4/5`; presenting one red state per gate — a
  driver with a type error, which `gatekit._said` already documents as `rc=1`, 0 bytes stdout — is
  the single most valuable follow-up and it needs `bend`, which this unit did not run.
- **The subdirectory blind spot** (§2): `gates/oracles/*.sh` and any future third gate home. Named
  by the control, not fixed by it.
- **Per-plant input assertions** (§5): the difference between a green that read its subject and a
  green that read nothing. Reported; not built.
- **`VERDICTS`/`PLANTS` for shell gates.** The declaration reader is `.py`-only. `checks/*.sh` are
  retired in favor of Python by `gates/README.md`, so this is a shrinking set — but it is not zero
  today, and those gates declare nothing here.
- **The tree moved while this ran** (113 → 114 entry points between two commands), so every number
  above carries the HEAD and time in the header. This is a census, not a constant.
