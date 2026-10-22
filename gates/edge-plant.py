#!/usr/bin/env python3
"""gates/edge-plant.py -- THE PLANT for `gates/edge-runner.py`, and its UNBROKEN CONTROL.

    .venv/bin/python gates/edge-plant.py        # every direction, on synthetic gates only
    .venv/bin/python gates/edge-runner.py --plant

WHAT A PLANT IS FOR HERE. The edge's whole claim is that it can NOTICE a gate that disagrees.
A check that has never been seen to fire is a check of unknown value -- `gates/gate-surface.py`'s
own rule -- and the two failures this file exists to refuse are the two the tree has already paid
for:

  * **A PLANT THAT CANNOT FAIL.** The first "negative" in this tree was vacuous: it flattened
    both sides to one constant, so it was satisfied by an instrument that did nothing.
  * **A PLANT THAT IS ONLY A NEGATIVE.** A runner that always answers FAIL satisfies a negative
    and is broken; a runner that always answers PASS satisfies a control and is broken.

**THE FALSIFICATION CLAUSE, STATED BEFORE THE ASSERTIONS SO A READER CAN CHECK IT.**
A runner that always answers `FAIL` satisfies direction A and REFUTES direction B. A runner that
always answers `PASS` satisfies direction B and REFUTES direction A. A runner that answers `DEAD`
for everything satisfies NEITHER A nor B, because A demands `FAIL` and B demands `PASS` and both
are demanded of the SAME runner over gates that differ only in their own exit code. **Only a
runner that reads the gate's own exit satisfies A and B together**, and C, D, E and G are about
the selection, the bookkeeping and the escape hatch rather than the verdict. So no constant
satisfies this suite: the plant is not a shape a broken runner can wear.

**THE SEVEN DIRECTIONS.**

  A  a gate that DISAGREES is recorded `FAIL` and the edge's own exit is `FAIL` (1).
  B  THE CONTROL: a gate that AGREES is recorded `PASS` and the edge's own exit is `PASS` (0).
  C  a candidate with NO cost-ledger row is RUN -- a gate nobody measured is never silently
     skipped, and the ledger is a measurement rather than a hand list.
  D  an EMPTY selection is `DEAD` (5), never `PASS`: an edge that measured nothing having exited
     0 is worse than no edge, because it is trusted.
  E  a candidate whose MEASURED cost is over the budget is `SKIP`ped, and its row says the number.
  F  INERTNESS: the live `gates/edge-trace.rows` and `gates/edge-cost.rows` are byte-identical
     before and after the plant. A plant that writes the state it audits measures its own damage.
  G  THE ESCAPE HATCH: a gate that DECLARES `RED_IS = "FINDING"` in its own source is red BY
     DESIGN, so the edge COUNTS it and does NOT charge it -- and the control for that arm is a
     gate that is identical except for the declaration and DOES charge.
  H  **A GATE THAT CANNOT START IS `REFUSED`, NOT `DEAD`** -- and the control for that arm is a
     gate that CAN start, measured normally in the same run. **`DEAD` MEANS "IT RAN AND EMITTED
     NOTHING", and a gate that never found its compiler never ran.** MEASURED 2026-10-22: a
     clean checkout has no `bin/bend` (`.gitignore:5`, and `git ls-tree -r HEAD -- bin/` is
     EMPTY), every GitHub Actions run of `.github/workflows/edge-gates.yml` IS a clean checkout,
     and the nine gates that need the compiler died there with `FileNotFoundError` and were
     recorded `DEAD, TRACEBACK` -- a verdict about a tree, about a gate that never ran. THIS
     ARM IS THE ONE THAT CATCHES IT, AND IT IS NOT VACUOUS: against the pre-fix
     `gates/gatekit.py` the same scenario answers `DEAD, TRACEBACK` and this arm FAILS.

**EVERY GATE THE PLANT RUNS IS SYNTHETIC AND LIVES IN A TEMP DIRECTORY.** Nothing here touches the
live tree's gates, and F asserts it.
"""
import importlib.util
import os
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# THE THREE SYNTHETIC GATES. The first two differ in ONE thing -- their own exit code and the
# word they print -- and that is the whole of the plant: a runner that cannot tell them apart
# is not reading the gate. The third is the escape hatch: it exits 1 for the same reason the
# second does, and the ONLY difference between them is the declaration.
AGREE = '''#!/usr/bin/env python3
import sys
print("the port and CPython agree on 1 row")
print("PASS")
sys.exit(0)
'''
DISAGREE = '''#!/usr/bin/env python3
import sys
print("row=1 the port says f32 and CPython says f16")
print("FAIL")
sys.exit(1)
'''
FINDING = '''#!/usr/bin/env python3
import sys
RED_IS = "FINDING"
print("30 of 39 gates declare a surface; 9 have been seen to fire")
print("FAIL")
sys.exit(1)
'''

# H: A GATE WHOSE COMPILER IS NOT THERE. **THE TEXT IS WRITTEN TO DISK**, because a plant that
# reads its subject out of git plants nothing the moment HEAD carries the defect's fix -- and a
# plant that MUTATES a tracked file is a plant that damages the tree it audits.
NO_TOOLCHAIN = '''#!/usr/bin/env python3
"""no-toolchain-gate.py -- A GATE WHOSE COMPILER IS NOT THERE, and it SAYS SO.

It is written into a COPY of the tree's `gates/` directory, so `from gatekit import Gate`
resolves to the COPY -- and the copy has to WORK, because the tree is PASSED IN
(`TINYGRAD_ROOT`), not found by walking upward out of a temp directory.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate

GATE = Gate("edge-plant-no-toolchain", bend="driver.bend", oracle="oracle.py", rows=1)
sys.exit(GATE.run())
'''


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def plants():
    """Every direction, and the count is COMPUTED from the checks -- a number a reader has to
    trust the prose for is the defect this file exists beside."""
    ed = load("edge_under_plant", HERE / "edge-runner.py")
    gs, _popmod, _gk = ed.modules()
    checks = []

    live = [ed.TRACE, ed.COST]
    before = {p: p.read_bytes() if p.is_file() else None for p in live}

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        good = tmp / "agree-gate.py"
        bad = tmp / "disagree-gate.py"
        finding = tmp / "finding-gate.py"
        good.write_text(AGREE)
        bad.write_text(DISAGREE)
        finding.write_text(FINDING)

        # (a) THE NEGATIVE THAT CAN FAIL, (b) THE UNBROKEN CONTROL, and (g) THE ESCAPE HATCH,
        # over the SAME runner.
        members = [(good, "py-main"), (bad, "py-main"), (finding, "py-main")]
        cands = {ed.rel_of(good, tmp): [("PIN", [("x", 1)])],
                 ed.rel_of(bad, tmp): [("PIN", [("x", 1)])],
                 ed.rel_of(finding, tmp): [("PIN", [("x", 1)])]}
        rows = ed.trace_rows(members, cands, sorted(cands), {}, gs, 30, 2048, root=tmp)
        by = {r[0]: r for r in rows}
        good_row = by[ed.rel_of(good, tmp)]
        bad_row = by[ed.rel_of(bad, tmp)]
        find_row = by[ed.rel_of(finding, tmp)]
        rc_all, _counts = ed.edge_verdict(rows)

        # A: the disagreeing gate is recorded FAIL, and the edge's own exit is FAIL.
        a = bad_row[2] == "FAIL" and bad_row[1] == "RAN"
        # B: THE CONTROL -- the agreeing gate is recorded PASS, and ALONE it leaves the edge PASS.
        b = good_row[2] == "PASS" and good_row[1] == "RAN"
        # AND THE TWO TOGETHER: the disagreeing gate CHARGES the edge. This is the arm a runner
        # that always answers FAIL satisfies and a runner that always answers PASS refutes.
        both = ed.edge_verdict([bad_row])[0] == FAIL
        only_good = ed.edge_verdict([good_row])[0] == PASS
        # G: THE ESCAPE HATCH -- a gate that DECLARES `RED_IS = "FINDING"` is red for its own
        # reasons, and the edge COUNTS it without CHARGING it. WITHOUT THIS ARM the edge would
        # be permanently red over a gate that is red BY DESIGN, and a gate that cannot pass
        # teaches nothing. The CONTROL for this arm is `bad_row`, which is identical except for
        # the declaration and DOES charge -- so the arm cannot be satisfied by "never charge".
        g = (find_row[2] == "FAIL" and find_row[1] == "RAN-FINDING"
             and ed.edge_verdict([find_row])[0] == PASS
             and ed.edge_verdict([bad_row])[0] == FAIL)

        # C: a candidate with NO ledger row is RUN. A hand list of gates would skip it.
        c = ed.select(cands, {}, 30)[0] == sorted(cands)
        # E: a candidate whose MEASURED cost is over the budget is SKIPped, and the row says it.
        ledger = {ed.rel_of(bad, tmp): [ed.rel_of(bad, tmp), "999.00", "10", "SKIP", "TIMED-OUT",
                                          "2026-10-20T00:00:00Z"]}
        sel, skip = ed.select(cands, ledger, 30)
        e = ed.rel_of(bad, tmp) in skip and ed.rel_of(bad, tmp) not in sel
        erow = ed.trace_rows(members, cands, sel, ledger, gs, 30, 2048, root=tmp)
        e_row = {r[0]: r for r in erow}[ed.rel_of(bad, tmp)]
        e = e and e_row[1] == "OVER-BUDGET" and "999.00" in e_row[3]

        # D: an EMPTY selection is DEAD, never PASS.
        d = ed.edge_verdict([])[0] == DEAD

    # H: A GATE THAT CANNOT START IS REFUSED, NOT DEAD.
    #
    # **WHAT IT REPRODUCES, EXACTLY.** `.gitignore:5` ignores `/bin/bend` and
    # `git ls-tree -r HEAD -- bin/` is EMPTY, so a CLEAN CHECKOUT HAS NO COMPILER -- and every
    # GitHub Actions run of `.github/workflows/edge-gates.yml` IS a clean checkout. MEASURED
    # 2026-10-22 in a clean checkout of this tree: `gates/mixin-op-gate.py` exited 1 in 0 s at
    # 21 MB with `FileNotFoundError: .../bin/bend`, and the tree's own classifier
    # (`checks/gatesweep.py:classify()`) answered `("DEAD", "TRACEBACK")` -- which says "it ran
    # and emitted nothing" about a gate that NEVER RAN. **`DEAD` IS A VERDICT ABOUT THE TREE
    # AND THIS IS NOT ONE.** The absent compiler is a PRECONDITION THAT WAS ABSENT, and the
    # tree's own word for that is `REFUSED`.
    #
    # **THE FAKE TREE IS A CLEAN CHECKOUT, AND THE GATE IS A COPY.** `gates/gatekit.py` and
    # `gates/bend-absent.py` are COPIED beside the synthetic gate, so the copy has to find its
    # own module, and THE TREE IS PASSED IN (`TINYGRAD_ROOT`) rather than found by walking
    # upward out of a temp directory -- `gates/reporoot.py`'s shape, which cannot answer here.
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "tree"
        (tree / "gates").mkdir(parents=True)
        (tree / "tinybendygrad").mkdir()
        (tree / "tinygrad").mkdir()
        (tree / "pyproject.toml").write_text("")
        os.symlink(ROOT / ".venv", tree / ".venv")
        for name in ("gatekit.py", "bend-absent.py"):
            shutil.copy2(HERE / name, tree / "gates" / name)
        (tree / "driver.bend").write_text("x = 1\n")
        (tree / "oracle.py").write_text("print('row=1 x=1')\n")
        gate = tree / "gates" / "no-toolchain-gate.py"
        gate.write_text(NO_TOOLCHAIN)
        agree = tree / "gates" / "agree-gate.py"
        agree.write_text(AGREE)
        saved = {k: os.environ.get(k) for k in (ed.TREE_ENV, "PYTHONPATH")}
        try:
            ed.pass_the_tree_in(tree)
            hmembers = [(gate, "py-main"), (agree, "py-main")]
            hcands = {ed.rel_of(gate, tree): [("PIN", [])],
                      ed.rel_of(agree, tree): [("PIN", [])]}
            hrows = ed.trace_rows(hmembers, hcands, sorted(hcands), {}, gs, 30, 2048, root=tree)
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        hby = {r[0]: r for r in hrows}
        h_row = hby[ed.rel_of(gate, tree)]
        c_row = hby[ed.rel_of(agree, tree)]
        # THE CLAIM: a gate that CANNOT START is REFUSED, and it is NOT DEAD.
        h = h_row[2] == "REFUSED" and h_row[2] != "DEAD"
        # THE CONTROL: a gate that CAN START is still measured normally, in the SAME run and
        # with the SAME tree passed in -- so this arm cannot be satisfied by "refuse everything".
        hcontrol = c_row[2] == "PASS" and c_row[1] == "RAN"

    checks.append(("A: a gate that DISAGREES is recorded FAIL", a,
                   f"row={bad_row[1]}/{bad_row[2]} rc={bad_row[4]}"))
    checks.append(("B: THE CONTROL -- a gate that AGREES is recorded PASS, and ALONE it leaves "
                   "the edge PASS", b and only_good, f"row={good_row[1]}/{good_row[2]}"))
    checks.append(("A+B TOGETHER: the disagreeing gate CHARGES the edge and the agreeing one "
                   "does not", both and rc_all == FAIL, f"both={rc_all}"))
    checks.append(("G: THE ESCAPE HATCH -- a gate that DECLARES `RED_IS = \"FINDING\"` is red "
                   "BY DESIGN, is COUNTED, and does NOT charge the edge", g,
                   f"row={find_row[1]}/{find_row[2]}"))
    checks.append(("C: a candidate with NO cost-ledger row is RUN, never skipped", c,
                   f"selected={len(ed.select(cands, {}, 30)[0])}/{len(cands)}"))
    checks.append(("D: an EMPTY selection is DEAD (5), never PASS", d, ""))
    checks.append(("E: a candidate over the measured budget is SKIPped, and its row says the "
                   "measured cost", e, f"row={e_row[1]}/{e_row[3]}"))
    checks.append(("H: a gate that CANNOT START (no compiler) is REFUSED, and is NOT DEAD",
                   h, f"row={h_row[1]}/{h_row[2]} rc={h_row[4]}"))
    checks.append(("H CONTROL: a gate that CAN START is still measured normally, in the same "
                   "run and with the same tree passed in", hcontrol,
                   f"row={c_row[1]}/{c_row[2]}"))

    after = {p: p.read_bytes() if p.is_file() else None for p in live}
    inert = before == after
    checks.append(("F: INERTNESS -- the live trace and the live cost ledger are byte-identical "
                   "before and after the plant", inert,
                   "unchanged" if inert else "CHANGED -- the plant wrote the live state"))

    rc = 0
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    print("FALSIFICATION: a runner that always answers FAIL satisfies A and refutes B; one that "
          "always answers\n              PASS satisfies B and refutes A; one that answers DEAD for "
          "everything satisfies neither.\n              Only a runner that reads the gate's OWN "
          "exit satisfies A and B together.")
    return rc


if __name__ == "__main__":
    sys.exit(plants())
