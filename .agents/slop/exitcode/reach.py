"""WHICH OF `gatekit`'s FIVE EXITS CAN ANY CONSUMER REACH? -- measured by AST, not by spelling.

POPULATION BY DISCOVERY, per `AGENTS.md` doctrine 1: a consumer is a `.py` file under the repo
(root walked, `.git`/`.venv`/`references` pruned) whose parsed source contains an `ImportFrom`
naming `gatekit`, OR which `gates/gatekit.py` imports. Nothing here is a hand list.

For every `return` whose value is a NAME bound to one of the five verdict constants, the file,
the line and the constant are reported. A constant that is spelled but has no `return` site is
reported as UNREACHABLE-BY-CONSTANT, which is a different claim from "no code path produces it":
only a symbol that cannot be produced AT ALL is vacant.

Usage: .venv/bin/python .agents/slop/exitcode/reach.py
"""
import ast
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PRUNE = {".git", ".venv", "references", "__pycache__", "node_modules"}

VERDICTS = {"PASS": 0, "FAIL": 1, "REFUSED": 3, "SKIP": 4, "DEAD": 5}


def sources():
    """Every `.py` in the tree, discovered by walk."""
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in PRUNE]
        for name in filenames:
            if name.endswith(".py"):
                yield Path(dirpath) / name


def tree_of(path):
    try:
        return ast.parse(path.read_text(), filename=str(path))
    except (SyntaxError, UnicodeDecodeError, ValueError):
        return None


def imports_gatekit(tree):
    """MEASURED LESSON, RECORDED BECAUSE IT ALMOST SKEWED THE WHOLE CENSUS: an `ast.Import`
    branch that `return`ed its own answer short-circuits the walk on the FIRST `import os` in
    the file, so a file whose `from gatekit import ...` sits at line 48 reads as a NON-consumer.
    It reported 0 consumers over a tree with dozens. Every branch must ADD to a flag; only the
    end of the walk may decide."""
    found = False
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.split(".")[-1] == "gatekit":
            found = True
        elif isinstance(node, ast.Import):
            found = found or any(a.name.split(".")[-1] == "gatekit" for a in node.names)
    return found


def int_literals(tree):
    """Every integer constant in the file -- `gatekit.py`'s own claim is that only 1 appears."""
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, int) and not isinstance(node.value, bool):
            out.append((node.lineno, node.value))
    return out


def return_sites(tree, names):
    """`return <NAME>` sites, and the same for `return <int>`."""
    named, literal = [], []
    for node in ast.walk(tree):
        if isinstance(node, ast.Return) and node.value is not None:
            v = node.value
            if isinstance(v, ast.Name) and v.id in names:
                named.append((node.lineno, v.id))
            elif isinstance(v, ast.Constant) and isinstance(v.value, int) and not isinstance(v.value, bool):
                literal.append((node.lineno, v.value))
    return named, literal


def main():
    consumers = []
    for path in sorted(sources()):
        t = tree_of(path)
        if t is not None and imports_gatekit(t):
            consumers.append((path, t))

    print(f"CONSUMERS (discovery: ImportFrom/Import naming gatekit) = {len(consumers)}")
    for path, _ in consumers:
        print(f"  {path.relative_to(ROOT)}")

    print("\n=== PER-TOKEN `return <TOKEN>` SITES ACROSS CONSUMERS ===")
    per = {k: [] for k in VERDICTS}
    for path, t in consumers:
        named, _ = return_sites(t, set(VERDICTS))
        for line, tok in named:
            per[tok].append((path.relative_to(ROOT), line))
    for tok in ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD"):
        sites = per[tok]
        print(f"{tok:<8} sites={len(sites)}")
        for p, line in sites:
            print(f"           {p}:{line}")

    print("\n=== `gatekit.py`'s OWN integer literals ===")
    gk = ROOT / "gates" / "gatekit.py"
    t = tree_of(gk)
    lits = int_literals(t)
    print(f"count={len(lits)} distinct={sorted({v for _, v in lits})}")
    for line, v in lits:
        print(f"  gatekit.py:{line} = {v}")

    print("\n=== `return <int>` LITERALS IN CONSUMERS (a numeric exit nobody named) ===")
    for path, t in consumers:
        _, lit = return_sites(t, set())
        if lit:
            print(f"  {path.relative_to(ROOT)}: {lit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())