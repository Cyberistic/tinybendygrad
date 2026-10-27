#!/usr/bin/env python3
"""falsify.py -- IS `RED_IS = "FINDING"` DECORATION?  THE SAME GATE, ONE LINE DELETED.

    .venv/bin/python .agents/slop/redis-class/falsify.py

WHAT IT MEASURES.  `gates/gate-surface.py` reads `RED_IS` out of each gate's OWN module body and
classes a red `FINDING` when it is declared AND the gate's rc-0 plant reached 0.  **A DECLARATION
THAT CANNOT CHANGE THE ANSWER IS DECORATION**, so the measurement here is the ONE THAT MATTERS:
the SAME gate, with the `RED_IS` line DELETED, read by the SAME census.  If the two copies land in
the same class, the declaration is decoration and the class it produces is a label.

THIS IS `gates/gate-surface.py`'s OWN PLANT 4a/4b, applied to the REAL gates instead of to a
synthetic one: 4a is a gate that ships `RED_IS` and is class FINDING, 4b is THE SAME GATE with the
constant deleted and is class FAILURE.

WHY A TEMPLATE AND NOT A COPY.  Two constraints, both measured:
  * `gates/gates-pop.py` admits only the files the COMMIT TREE CARRIES ("a file the commit tree
    does not carry is not a gate of this repository"), so a copy dropped into the working tree is
    INVISIBLE to the census -- it is not read, so it cannot be a witness.
  * `reach()` runs a plant with `cwd=ROOT`, the REAL tree, so a copy in a TEMP tree resolves
    `HERE.parents[0]` against the temp tree and REFUSES for want of its inputs.
SO THE GATE IS PLACED IN A TEMP TREE AS A TEMPLATE: its own body, with the repo-root CONSTANTS
REWRITTEN to the real tree's absolute paths.  Every file it then reads is the REAL file, and the
census reads the `RED_IS` off the template's OWN module body -- which is the declaration under
test.  NOTHING IN THE REAL TREE IS WRITTEN.

THE CONSTANT REWRITES ARE THE WHOLE TRICK, and they are per gate because each file spells its root
differently -- the same `parents[N]` class `checks/dup-gate.py:59` documents.  A rewrite that
misses leaves the gate reading a temp tree it cannot find, and the census then says `UNTAKEN`,
which is a TRUE SENTENCE ABOUT THE TEMPLATE and a FALSE ONE ABOUT THE GATE.  So the run prints
the class of BOTH states and the reader can see a `UNTAKEN` rather than being handed a `FINDING`
that a broken template produced.
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
GATES = [
    "checks/dup-gate.py",
    "checks/env-precond.py",
    "checks/norm_check.py",
    "checks/render-gate-oracle-gate.py",
    "checks/residue.py",
]


def load_surface():
    """`gates/gate-surface.py`, LOADED BY PATH.  `gates/` is not a package, and a loader that
    bound a name could be shadowed by any file in the tree -- the rule `gates/gate-surface.py`
    states for its own `gates-pop` loader."""
    p = ROOT / "gates" / "gate-surface.py"
    spec = importlib.util.spec_from_file_location("gate_surface", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def template(src: str) -> str:
    """The gate's body with its repo-root CONSTANTS pointed at the REAL tree."""
    out = src.replace("REPO = HERE.parents[0]", f"REPO = pathlib.Path({str(ROOT)!r})")
    out = out.replace("REPO = pathlib.Path(__file__).resolve().parent.parent",
                      f"REPO = pathlib.Path({str(ROOT)!r})")
    out = out.replace("HERE = pathlib.Path(__file__).resolve().parent",
                      f"HERE = pathlib.Path({str(ROOT / 'checks')!r})")
    out = out.replace("REPO = HERE.parent", f"REPO = pathlib.Path({str(ROOT)!r})")
    out = out.replace("ROOT = pathlib.Path(__file__).resolve().parents[1]",
                      f"ROOT = pathlib.Path({str(ROOT)!r})")
    out = out.replace("HERE = os.path.dirname(os.path.abspath(__file__))",
                      f"HERE = {str(ROOT / 'checks')!r}")
    out = out.replace("ROOT = os.path.dirname(HERE)", f"ROOT = {str(ROOT)!r}")
    return out


def klass_of(gs, src: str, name: str) -> str:
    """The census's class for ONE gate, over a synthetic tree that holds it."""
    with tempfile.TemporaryDirectory() as td:
        r = pathlib.Path(td)
        gs._tree(r)
        (r / "gates" / "gatekit.py").write_text((ROOT / "gates" / "gatekit.py").read_text())
        (r / "checks" / name).write_text(src)
        _rc, said = gs._run_report(r)
    for line in said.splitlines():
        if f"checks/{name}" in line and "red=" in line:
            return line.split("red=")[1].split()[0]
    return "?"


def main() -> int:
    gs = load_surface()
    print(f"{'gate':34} {'as-is':>10} {'RED_IS deleted':>16}   falsifiable?")
    bad = 0
    for g in GATES:
        p = ROOT / g
        src = template(p.read_text())
        stripped = re.sub(r'(?m)^RED_IS = "FINDING"\n', "", src)
        a = klass_of(gs, src, p.name)
        b = klass_of(gs, stripped, p.name)
        declared = gs.declaration(p)[2]
        moves = a != b
        if declared and not moves:
            bad += 1
        print(f"{g:34} {a:>10} {b:>16}   {'CLASS MOVES' if moves else 'same'}"
              f"   (declared RED_IS={declared!r})")
    print()
    print(f"REDIS: {'RED' if bad else 'OK'} -- {bad} declared RED_IS that does NOT move the class. "
          f"A declaration\n  that cannot change the answer is decoration, and a class that cannot "
          f"be false is a label.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
