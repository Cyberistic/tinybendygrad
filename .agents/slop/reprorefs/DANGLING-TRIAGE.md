# The 108 DANGLING rows, triaged: none of them is a live instrument missing a required input

**2026-10-15, HEAD `b1d95705d`.** `checks/repro-paths.py` reports 108 dangling paths among 716 named by
543 committed reports. A raw 108 says nothing about whether the tree is broken, so this splits the
population by **DANGER CLASS** and adjudicates every row a live instrument names.

## THE SPLIT, WITH ITS DENOMINATOR

| class | n | what it means |
| --- | --- | --- |
| named only by finished units' reports | **99** | a historical record naming a tool that was pruned. Naming it is what happened, and the report is not wrong. |
| named by a live instrument's text | **9** | adjudicated below. |

The 9 are **NOT** 9 broken inputs. Read at the citing line, **every one is prose, a mapping key, or a
declared-but-absent input whose absence is deliberately counted**:

| dangling path | cited by | the citing line says |
| --- | --- | --- |
| `.agents/slop/abi/abi.json` | `jsfix_gate.py:15` | *"this file cites it **by id** and does"* — never opens it |
| `.agents/slop/guardfix/probe-c.bend` | `checks/substrate.py:120` | *"was **NEVER COMMITTED**"* — documents the absence |
| `.agents/slop/quiesce/snapshot.py` | `checks/differ.py:882` | a comment about what a hand-list entry *would* be |
| `.agents/slop/schedule-bodies/BEFORE-rows.txt` | `oracle-txt-census.py:253` | *"which is **ABSENT**. A basename join"* — documents why it must not be joined |
| `checks/abi_gate.py.fixed` | `gates-pop.py:1154,1390` | `out["checks/abi_gate.py.fixed"] = GOOD_ROOT` — a **mapping KEY**, not a path read |
| `checks/nl-port-post.txt` | `nl-gate.py:420` | *"is in **NO commit** (`git log --all` answers nothing)"* |
| `.agents/slop/shlscope/gate.sh` | `gate.sh` | a `.agents/slop/` scratch script, not a live instrument |
| `.agents/slop/triage/allfiles.txt` | `demo.sh` | likewise a scratch script |
| `.agents/slop/graphcmp-dbg.bend` | `checks/substrate-snapshot.py:78` | `COPIES`, and `inputs()` is *"every one of them, **whether or not it is on disk**… THE `else` IS THE WHOLE FIX"* — a DECLARED input whose absence is counted, the same rule as `differ.py`'s `SUBSTRATE_INPUTS` |

## AND THE FIRST COUNT WAS WRONG, IN THE WAY THIS REPO PUNISHES

The first pass reported **15** dangerous. **Seven of the 15 were `checks/repro-paths.py` citing ITSELF** —
its docstring deliberately names those six instruments as *"the historical incident that motivated this
gate"*, and they are gone because they were never committed. **An instrument that scans every file
including itself counts its own narrative as a broken input.** Excluding the gate's own history gives 9,
and adjudicating those gives 0.

## WHAT THIS MEANS FOR THE GATE'S CLAIM

`checks/repro-paths.py` opens with *"Every path a committed report tells a reader to run must exist."*
MEASURED: **0 of its 108 rows is a reader being told to run something that is not there.** They are
records of what ran, and a record that names a pruned tool is accurate, not broken.

So the 108 is **stale historical prose**, and the gate's CLAIM is currently **overstated for its
population** — which is doctrine 1's mirror image: not a population too small, but a claim larger than
the population supports. It is NOT fixed here. Narrowing the claim, or splitting historical records
from live instructions, is a redesign of what the gate asserts, and **prefer refuse to repair** applies
with full force: a wrong-claim fix that guesses which reports are historical would silence the one row
class that is genuinely worth a reader's attention.

**Reproduce**: `checks/repro-paths.py` for the 108; the split is a walk of `checks/*.py`,
`checks/*.sh`, `gates/*.py` and `bin/*` asking which name each dangling path.