#!/usr/bin/env python3
"""IS `gatekit`'s `SKIP` (4) REACHABLE AT ALL? AST, over `gates/gatekit.py`'s own body.

    .venv/bin/python .agents/slop/synonyms/reach.py

A collision between two MEANINGS on one number is much easier to settle when one of the two
meanings has no SITE. `gatekit.py:60` declares `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`
and the census above finds NO `return SKIP` in the file. **So the question "is `wallcheck`'s 4 the
same verdict as `SKIP`?" may be unanswerable because `SKIP` is a slot the owner never fills --
which would make the collision a NAMED VERDICT COLLIDING WITH A HOLE, not with a live verdict.**

Read by AST (`Return` nodes and `Name` loads), because a grep for `SKIP` also matches the
definition on line 60 and every docstring that mentions the word -- which is how a gate's own
`AGENTS.md` sentence about SKIP reads as evidence that SKIP is returned.
"""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATEKIT = ROOT / "gates" / "gatekit.py"
WALLCHECK = ROOT / "checks" / "wallcheck.py"


def returns_of(path, name):
    """Every line that RETURNS the bare name `name`, by AST. `return SKIP` only."""
    tree = ast.parse(path.read_text(errors="replace"))
    hits = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Return) and isinstance(node.value, ast.Name):
            if node.value.id == name:
                hits.append(node.lineno)
    return hits


def exits_of(path):
    """Every `return <int literal>` and `sys.exit(<int literal>)`, by AST."""
    tree = ast.parse(path.read_text(errors="replace"))
    out = []
    for node in ast.walk(tree):
        val = None
        if isinstance(node, ast.Return) and isinstance(node.value, ast.Constant):
            val = node.value.value
        elif (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
              and node.func.attr == "exit" and node.args
              and isinstance(node.args[0], ast.Constant)):
            val = node.args[0].value
        # `type(val) is int`, NOT `isinstance(val, int)`. `bool` IS a subclass of `int` in
        # Python, so the first run of this file reported `False` and `True` as integer exits and
        # printed "DISTINCT integer exits: [False, True]" for a file that returns NO integer
        # literals at all in that shape. MEASURED, not hypothesised -- and it is the same class
        # of defect as `prune4`'s, a shape that matches where a MEANING was wanted.
        if type(val) is int:
            out.append((node.lineno, val))
    return sorted(out)


def main():
    print("OWNER gates/gatekit.py -- every site that RETURNS one of its five names, by AST:\n")
    total = 0
    for name in ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD"):
        h = returns_of(GATEKIT, name)
        total += len(h)
        print(f"  return {name:8} -> {len(h)} site(s)  {h}")
    print(f"\n  TOTAL return sites for the five names: {total}")

    print("\ngatekit.py -- every INTEGER literal returned or exited, by AST:")
    for line, v in exits_of(GATEKIT):
        print(f"  :{line:<4} {v}")
    lit = sorted({v for _l, v in exits_of(GATEKIT)})
    print(f"\n  DISTINCT integer exits in gates/gatekit.py: {lit}")
    print(f"  Of those, the literal 4 appears {'YES' if 4 in lit else 'NO'} -- so exit 4 is "
          f"{'reachable' if 4 in lit else 'NOT REACHABLE from any integer literal in the owner'}")

    print("\nchecks/wallcheck.py -- every INTEGER literal returned or exited, by AST:")
    wl = sorted({v for _l, v in exits_of(WALLCHECK)})
    for line, v in exits_of(WALLCHECK):
        print(f"  :{line:<4} {v}")
    print(f"\n  DISTINCT integer exits in checks/wallcheck.py: {wl}")

    print("\nTHE CHARGE, AS A RUNNER APPLIES IT (`hooks/run.py:116`):")
    print("    rc in {0,1,3,4,5} -> scored under its own name; ANY OTHER rc -> DEAD (5)")
    for c, n in ((0, "PASS/GREEN"), (1, "FAIL"), (2, "?"), (3, "REFUSED"), (4, "SKIP"),
                 (5, "DEAD")):
        print(f"    {c} -> {('DEAD  <-- a gate that REFUSED is scored as having crashed' if c == 2 else n)}")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())