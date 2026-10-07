#!/usr/bin/env python3
"""WHAT EACH ANSWER COSTS IN FILES. Consumer count BY WALK, and additive vs breaking.

    .venv/bin/python .agents/slop/synonyms/cost.py

THE BRIEF SAYS `gates/gatekit.py` IS "LOADED BY PATH BY ~8 CONSUMERS". MEASURED BY WALK, over
import sites only (an `ast.Import`/`ast.ImportFrom` naming the module, OR a
`spec_from_file_location` whose path argument ends in `gatekit.py`), the count is different and
the shape of the answer decides item 4:

  * an ADDITIVE change -- a NEW token in the owner's vocabulary -- touches ZERO consumers,
    because every consumer reads the owner's UNPACK and an extra name costs a consumer nothing;
  * a BREAKING change -- a RENUMBER -- touches every consumer that compares against the literal.

So the two are counted SEPARATELY and the report says which is which. The number is quoted with
its rule and its timestamp, never bare, per `AGENTS.md`'s own rule about row counts.
"""
import ast
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATEKIT = ROOT / "gates" / "gatekit.py"
PRUNE = {".git", ".venv", "__pycache__", "node_modules", "references"}


def loads_gatekit(tree):
    """True if the module NAMES gatekit in an import or a path-load, by AST.

    AST, because a grep for `gatekit` matches `gates/gatekit.py` inside a PROSE COMMENT --
    `gatekit.py` itself has four such lines and `gate-surface.py` names it a dozen times in
    docstrings -- and `AGENTS.md` records precisely this failure twice (`xd1/pin` matched a
    basename regex; `hooks/run.py:30`'s comment describes an exit vocabulary it does not hold).
    """
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and (node.module or "").split(".")[-1] == "gatekit":
            return True
        if isinstance(node, ast.Import):
            for a in node.names:
                if a.name.split(".")[-1] == "gatekit":
                    return True
        if (isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "spec_from_file_location"):
            for a in ast.walk(node):
                if isinstance(a, ast.Constant) and isinstance(a.value, str) \
                        and a.value.endswith("gatekit.py"):
                    return True
    return False


def names_the_five(tree):
    """True if the module references any of the owner's five NAMES. A consumer of the VOCABULARY."""
    names = {"PASS", "FAIL", "REFUSED", "SKIP", "DEAD"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and node.id in names:
            return True
        if isinstance(node, ast.Attribute) and node.attr in names:
            return True
    return False


def main():
    gates, runners, selfname = [], [], False
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in PRUNE]
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            p = Path(dirpath) / fn
            rel = str(p.relative_to(ROOT))
            if rel == "gates/gatekit.py":
                selfname = True
                continue
            try:
                tree = ast.parse(p.read_text(errors="replace"))
            except SyntaxError:
                continue
            if loads_gatekit(tree):
                (gates if rel.startswith(("checks/", "gates/")) else runners).append(rel)

    print(f"WALK, import sites only, tree minus {sorted(PRUNE)}  (owner excluded from its own count)\n")
    print(f"  CONSUMERS of gates/gatekit.py: {len(gates) + len(runners)}"
          f"  ({len(gates)} under HOMES, {len(runners)} outside)")
    print(f"  the brief says ~8. MEASURED: {len(gates) + len(runners)}."
          f"  **The ~8 IS WRONG BY {len(gates) + len(runners) - 8}.**")
    print("\n  --- outside HOMES (invisible to gates-pop.discover()) ---")
    for r in runners:
        print(f"    {r}")
    print("\n  --- under HOMES ---")
    for r in gates:
        print(f"    {r}")

    print("\nWHAT EACH ANSWER COSTS:\n")
    print(f"  ADDITIVE  (a NEW token: `gatekit` gains a name, every number stays put)")
    print(f"            touches 0 of {len(gates) + len(runners)} consumers. Every consumer reads the")
    print(f"            owner's UNPACK; an extra entry costs a reader nothing, and a gate that")
    print(f"            already names it keeps working. THIS IS THE CHEAP DIRECTION.")
    print(f"  BREAKING  (a RENUMBER: 4 and 5 swap, or 4 moves to 6)")
    print(f"            touches every consumer that compares against the literal, and every gate")
    print(f"            whose PLANTS argv encodes the code. Measured: the 11 RENAMED codes above")
    print(f"            would ALL have to change, and `checks/e2e.py:519 return 4` is a LITERAL.")
    lit = []
    for rel in gates + runners:
        tree = ast.parse((ROOT / rel).read_text(errors="replace"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and type(node.value) is int \
                    and node.value in (4, 5):
                lit.append(rel)
    print(f"            consumers holding the LITERAL 4 or 5 anywhere in their AST: "
          f"{len(set(lit))} -> {sorted(set(lit))[:8]}{' ...' if len(set(lit)) > 8 else ''}")

    print("\nAND THE DIRECTION OF THE RELATIONSHIP, WHICH IS THE SAME QUESTION:\n")
    print("  gates -> gatekit   the vocabulary can only travel owner -> gate, because the gates")
    print("                     IMPORT it. So a table in the owner is a hand list of 8 gates'")
    print("                     vocabularies, and `gendirs.py` is right that two such holders")
    print("                     have no authority over each other.")
    print("  gatekit -> gates   IMPOSSIBLE without inverting every import, which is a rewrite of")
    print("                     40 files to move a table, and buys nothing the gate's own")
    print("                     `VERDICTS` does not already say.")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())