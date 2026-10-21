#!/usr/bin/env python3
"""gates/reachability-plant.py -- THE PLANT for `gates/reachability-gate.py`, and its CONTROL.

    .venv/bin/python gates/reachability-plant.py
    .venv/bin/python gates/reachability-gate.py --plant

WHAT A PLANT IS FOR HERE. The instrument's whole claim is that it can NOTICE a gate that
stopped being reachable, and that it REFUSES rather than passes when there is nothing to
compare. **A CHECK THAT HAS NEVER BEEN SEEN TO FIRE IS A CHECK OF UNKNOWN VALUE**, and the
tree has already paid for the two ways this goes wrong:

  * **A PLANT THAT CANNOT FAIL.** The first "negative" in this tree was vacuous: it flattened
    both sides to one constant, so it was satisfied by an instrument that did nothing.
  * **A PLANT THAT IS ONLY A NEGATIVE.** An instrument that always answers "reachable"
    satisfies a negative and is broken; one that always answers "not reachable" satisfies a
    control and is broken.

**THE FALSIFICATION CLAUSE, STATED BEFORE THE ASSERTIONS SO A READER CAN CHECK IT.** An
instrument that always answers REACHABLE satisfies P1 and refutes C1. One that always answers
UNREACHABLE satisfies C1 and refutes P1. One that always REFUSES satisfies P2 and refutes C2.
**Only an instrument that reads the tree satisfies all of them**, because P1 and C1 differ in
ONE THING -- whether the workflow's `run:` line names the gate -- and the workflow is the only
difference between the two trees.

**EVERY TREE THE PLANT MEASURES IS SYNTHETIC AND LIVES IN A TEMP DIRECTORY, AND IT IS BUILT
OUT OF COPIES.** `gates/gates-pop.py`, `gates/gatekit.py` and `gates/pincensus-pop.py` are
COPIED into the synthetic tree, because the census loads the tree's OWN instruments by path --
a plant that used the live tree's instruments would be measuring the live tree and calling the
result a plant. The home is earned the way a real one is earned: by a gate that certifies it
(`gates/gates-pop.py`'s own `GOOD_ROOT` fixture, used as a FIXTURE rather than retyped), so a
synthetic tree with no gate in it is a synthetic tree with NO POPULATION, which is what makes
P2's empty case possible at all.

THE DIRECTIONS.

  P1  a workflow that NAMES a gate makes that gate REACHABLE.
  C1  THE CONTROL: a workflow that names NOTHING leaves the gate UNREACHABLE, and the verdict
      is RED -- not green, and not a refusal. This is the control that makes P1 mean something.
  P2  an EMPTY workflow set is REFUSED (3), never PASS (0): "no gate is run" and "all gates
      are run" would otherwise look the same.
  C2  THE CONTROL for P2: a tree WITH a workflow is not refused for want of one.
  P3  THE CONTROL'S WHOLE POINT: a gate named ONLY BY AN UNREACHABLE GATE is still
      unreachable. A join that did not close transitively would report it reachable.
  P4  a gate the ledger records as reachable and that is not any more is RED.
  C4  THE CONTROL for P4: the same ledger and a tree where nothing moved is GREEN.
  F   INERTNESS: the live ledger and the live trace are byte-identical before and after the
      plant. A plant that writes the state it audits measures its own damage.
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# THE THREE SYNTHETIC GATES, and they differ in ONE THING each.
SYNTH = '''#!/usr/bin/env python3
import sys
if __name__ == "__main__":
    raise SystemExit(0)
'''
# THE NAMER: a gate that names `alpha-gate.py` and is named by NOTHING. It is the control for
# the transitive closure: whatever it names is named only by an unreachable gate.
NAMER = '''#!/usr/bin/env python3
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ALPHA = HERE / "alpha-gate.py"
if __name__ == "__main__":
    raise SystemExit(0)
'''
# A WORKFLOW THAT NAMES A GATE, AND ONE THAT NAMES NOTHING. They differ in ONE line, and that
# line is the whole of the instrument's claim.
WF_NAMES = """name: synthetic
on: [push]
jobs:
  synth:
    runs-on: ubuntu-latest
    steps:
      - run: .venv/bin/python gates/alpha-gate.py
"""
WF_NAMES_NONE = """name: synthetic
on: [push]
jobs:
  synth:
    runs-on: ubuntu-latest
    steps:
      - run: echo nothing here names a gate
"""
WF_NAMES_NAMER = """name: synthetic
on: [push]
jobs:
  synth:
    runs-on: ubuntu-latest
    steps:
      - run: .venv/bin/python gates/beta-gate.py
"""
WF_NAMES_OTHER = """name: synthetic
on: [push]
jobs:
  synth:
    runs-on: ubuntu-latest
    steps:
      - run: .venv/bin/python gates/gamma-gate.py
"""


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def build(root, gp, workflow=None):
    """-> a synthetic tree, built out of COPIES of the tree's own instruments.

    `gates/gates-pop.py`'s `_tree` earns the home the way a real one is earned -- with a gate
    that certifies it -- so the synthetic tree's population is DISCOVERED and not listed. The
    three instruments the census loads are COPIED in, because the census loads the tree's OWN
    instruments by path and a plant that used the live ones would be measuring the live tree.
    """
    root.mkdir(parents=True, exist_ok=True)
    gp._tree(root, "gates")
    for f in ("gates-pop.py", "gatekit.py", "pincensus-pop.py"):
        (root / "gates" / f).write_text((HERE / f).read_text())
    (root / "gates" / "alpha-gate.py").write_text(SYNTH)
    (root / "gates" / "beta-gate.py").write_text(NAMER)
    (root / "gates" / "gamma-gate.py").write_text(SYNTH)
    if workflow is not None:
        wf = root / ".github" / "workflows"
        wf.mkdir(parents=True, exist_ok=True)
        (wf / "synth.yml").write_text(workflow)
    return root


def plants():
    """Every direction, and the count is COMPUTED from the checks -- a number a reader has to
    trust the prose for is the defect this file exists beside."""
    rg = load("reach_under_plant", HERE / "reachability-gate.py")
    gp = load("reach_under_plant_pop", HERE / "gates-pop.py")
    if rg is None or gp is None:
        print("== REFUSED, NOT A VERDICT: the instrument under plant is gone", file=sys.stderr)
        return REFUSED
    checks = []

    live = [rg.LEDGER, rg.TRACE]
    before = {p: p.read_bytes() if p.is_file() else None for p in live}

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        # P1 / C1: THE SAME INSTRUMENT, TWO TREES THAT DIFFER IN ONE LINE.
        a = rg.census(build(tmp / "p1", gp, WF_NAMES))
        b = rg.census(build(tmp / "c1", gp, WF_NAMES_NONE))
        p1 = "gates/alpha-gate.py" in a.reachable
        c1 = "gates/alpha-gate.py" not in b.reachable
        # AND THE VERDICT: a root that names nothing is RED, not green and not a refusal.
        ledger_a = {"gates/alpha-gate.py": ("gates/alpha-gate.py", "-", "chain", "stamp")}
        rc_b, charges_b, _notes_b = rg.verdict(b, ledger_a)
        c1 = c1 and rc_b == FAIL and any("names NO gate" in c for c in charges_b)
        # AND THE CONTROL: the same ledger over the tree where the workflow DOES name the gate
        # is GREEN -- so a verdict that is always RED is refuted here.
        rc_a, charges_a, _notes_a = rg.verdict(a, ledger_a)
        c1 = c1 and rc_a == PASS and not charges_a

        # P2 / C2: THE EMPTY WORKFLOW SET IS REFUSED, AND A NON-EMPTY ONE IS NOT.
        d = rg.census(build(tmp / "p2", gp, None))
        rc_d, _ch, _no = rg.verdict(d, ledger_a)
        p2 = rc_d == REFUSED
        rc_e, _ch, _no = rg.verdict(a, ledger_a)
        c2 = rc_e != REFUSED

        # P3: THE CONTROL'S WHOLE POINT. `alpha-gate.py` is named by `beta-gate.py`, and
        # `beta-gate.py` is named by NOTHING, so alpha is named only by an unreachable gate.
        # The tree whose workflow names a THIRD gate is the one that shows it.
        g = rg.census(build(tmp / "p3", gp, WF_NAMES_OTHER))
        p3 = ("gates/alpha-gate.py" not in g.reachable
              and bool(g.named_by.get("gates/alpha-gate.py"))
              # AND EVERY NAMER OF IT IS UNREACHABLE -- that is the whole claim.
              and all(n[0] not in g.depth for n in g.named_by["gates/alpha-gate.py"])
              and "gates/beta-gate.py" not in g.reachable
              and "gates/gamma-gate.py" in g.reachable)
        # AND THE OTHER SIDE OF IT: when the workflow names the NAMER, the gate the NAMER names
        # IS reachable -- so P3 is a statement about the NAMER being unreachable, and not about
        # the join being blind to a naming.
        f = rg.census(build(tmp / "c3", gp, WF_NAMES_NAMER))
        p3 = p3 and "gates/alpha-gate.py" in f.reachable and "gates/beta-gate.py" in f.reachable

        # P4 / C4: THE LEDGER. A recorded-reachable gate that is not reachable any more is RED.
        rc_b2, charges_b2, _no = rg.verdict(b, ledger_a)
        p4 = rc_b2 == FAIL and any("no longer reachable" in c for c in charges_b2)
        rc_a2, charges_a2, _no = rg.verdict(a, ledger_a)
        c4 = rc_a2 == PASS

        # G: THE LEDGER ROUND-TRIPS. **THE FIRST VERSION OF THE LEDGER READER CONSUMED THE
        # FIRST DATA ROW AS A HEADER**, so it read 19 of its own 20 rows, and the row it
        # dropped was reported as "became reachable and is not in the ledger" -- a finding
        # about the READER, dressed as a finding about the tree. A ledger that silently drops a
        # row cannot be checked, so the write and the read are asserted against EACH OTHER.
        ledger_path = tmp / "ledger.tsv"
        rg.write_ledger(ledger_path, a)
        back = rg.read_ledger(ledger_path)
        gr = (back is not None and len(back) == len(a.reachable)
              and all(p in back for p in a.reachable))

    checks.append(("P1: a workflow that NAMES a gate makes that gate REACHABLE", p1,
                   f"reachable={sorted(a.reachable)}" if a else ""))
    checks.append(("C1: THE CONTROL -- a workflow that names NOTHING leaves the gate UNREACHABLE, "
                   "and the verdict is RED, and the same ledger over a tree that DOES name it is "
                   "GREEN", c1, f"red={rc_b} green={rc_a}"))
    checks.append(("P2: an EMPTY workflow set is REFUSED (3), never PASS (0)", p2,
                   f"rc={rc_d}"))
    checks.append(("C2: THE CONTROL -- a tree WITH a workflow is not refused for want of one",
                   c2, f"rc={rc_e}"))
    checks.append(("P3: a gate named ONLY by an UNREACHABLE gate is still unreachable -- and the "
                   "gate the workflow DOES name is reachable, and so is the gate the NAMER names "
                   "when the workflow names the NAMER", p3,
                   f"alpha reachable={sorted(g.reachable)}" if g else ""))
    checks.append(("P4: a recorded-reachable gate that is no longer reachable is RED", p4,
                   f"rc={rc_b2}"))
    checks.append(("C4: THE CONTROL -- the same ledger over a tree where nothing moved is GREEN",
                   c4, f"rc={rc_a2}"))
    checks.append(("G: the ledger ROUND-TRIPS -- every reachable gate the writer wrote is a row "
                   "the reader reads", gr,
                   f"wrote={len(a.reachable)} read={len(back) if back else 'NONE'}"))

    after = {p: p.read_bytes() if p.is_file() else None for p in live}
    inert = before == after
    checks.append(("F: INERTNESS -- the live ledger and the live trace are byte-identical before "
                   "and after the plant", inert,
                   "unchanged" if inert else "CHANGED -- the plant wrote the live state"))

    rc = 0
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    print("FALSIFICATION: an instrument that always answers REACHABLE satisfies P1 and refutes "
          "C1; one that always\n              answers UNREACHABLE satisfies C1 and refutes P1; one "
          "that always REFUSES satisfies P2 and refutes C2.\n              Only an instrument that "
          "reads the tree satisfies all of them, because P1 and C1 differ in ONE LINE.")
    return rc


if __name__ == "__main__":
    sys.exit(plants())
