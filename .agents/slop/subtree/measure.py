"""MEASURE THE GAP: `gates/gates-pop.py:discover()` is `iterdir()`-BASED and NON-RECURSIVE.

Question 1: is the walk `iterdir()` and what file:line?
Question 2: how many `.py`/`.sh` files live ONE LEVEL DEEPER than `discover()` walks, under
           `gates/` and `checks/`? Names, and whether a recursive walk would find them.
Question 6: what scope does `discover()` claim in its own name and docstring?

No gate is executed. `discover()` is a pure directory walk; this script imports the module BY PATH
(never by name, so nothing can shadow it) and reads its source text for the walk site.
"""
import ast
import importlib.util
import io
import os
import re
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "census.rows"


def by_path(p: Path, name: str):
    """Load a module by FILE PATH. `gates/` is not a package; importing it by name would let any
    file in the tree choose this instrument's population."""
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def walk_sites(path: Path):
    """`(lineno, text)` for every line of `path` whose source names a directory walk.

    Found by a REGEX OVER THE TREE'S OWN WRITE SITE, and the site is then printed verbatim so a
    reader can check the regex against the line it matched. A `discover` name is not evidence.
    """
    src = path.read_text()
    out = []
    for i, line in enumerate(src.splitlines(), 1):
        if re.search(r"iterdir|rglob|os\.walk|glob\(|os\.scandir|walk\(", line):
            out.append((i, line.strip()))
    return out


def fn_span(path: Path, name: str):
    """`(first, last)` 1-based line span of `def <name>` in `path`, by AST. Returns None if absent."""
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node.lineno, node.end_lineno
    return None


def docstring_of(path: Path, name: str) -> str:
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return ast.get_docstring(node) or ""
    return ""


def recursive(root: Path, homes, suffixes):
    """`{relpath}` for every suffix-matching file under `homes`, RECURSIVELY, minus `__pycache__`.

    This is `gates/gate-surface.py:walk_control`'s rule re-derived here, because the point of the
    measurement is that TWO rules disagree by one flag and the reader should see both.
    """
    out = set()
    for home in homes:
        h = root / home
        if not os.path.isdir(h):
            continue
        for dirpath, dirnames, filenames in os.walk(h):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith(suffixes):
                    out.add(str((Path(dirpath) / fn).relative_to(root)))
    return out


def main():
    rows = []

    def emit(*cells):
        rows.append("\t".join(str(c) for c in cells))

    gp_path = ROOT / "gates" / "gates-pop.py"
    gp = by_path(gp_path, "gp_measure")

    emit("CLAIM", "field", "value")
    span = fn_span(gp_path, "discover")
    emit("CLAIM", "discover_span", f"{span[0]}-{span[1]}")
    for ln, text in walk_sites(gp_path):
        emit("CLAIM", f"walk_site:{ln}", text)

    doc = docstring_of(gp_path, "discover")
    claims_recursion = bool(re.search(r"recursiv|subdirector|deeper|descend into sub", doc, re.I))
    # "not descended into" is a NEGATED claim about recursion. Both readings must be named.
    negated = bool(re.search(r"not\s+descended|not\s+recursiv", doc, re.I))
    emit("CLAIM", "doc_claims_recursion", claims_recursion)
    emit("CLAIM", "doc_negates_recursion", negated)
    emit("CLAIM", "doc_len", len(doc.split()))
    for ln, text in walk_sites(gp_path):
        if text not in doc:
            continue
    emit("CLAIM", "doc_first_40", " ".join(doc.split()[:40]))

    # ---- the measurement ----
    entries, libs = gp.discover(ROOT)
    disc = {str(p.relative_to(ROOT)) for p in list(entries) + list(libs)}
    walk = recursive(ROOT, gp.HOMES, gp.SUFFIXES)
    deeper = sorted(walk - disc)

    emit("MEASURE", "homes", "/".join(gp.HOMES))
    emit("MEASURE", "suffixes", "/".join(gp.SUFFIXES))
    emit("MEASURE", "discover_entries", len(entries))
    emit("MEASURE", "discover_libs", len(libs))
    emit("MEASURE", "discover_total", len(disc))
    emit("MEASURE", "recursive_walk_total", len(walk))
    emit("MEASURE", "only_discover", len(disc - walk))
    emit("MEASURE", "only_walk", len(walk - disc))
    for rel in deeper:
        emit("DEEPER", rel, gp.entry_reason(ROOT / rel))

    # ---- what a consumer COUNTS, vs what exists ----
    emit("DENOM", "gates_top_level_py_sh", len([r for r in disc if r.count("/") == 1]))
    emit("DENOM", "deeper_py_sh", len(deeper))
    emit("DENOM", "under_gates_deeper", len([r for r in deeper if r.startswith("gates/")]))
    emit("DENOM", "under_checks_deeper", len([r for r in deeper if r.startswith("checks/")]))

    # ---- does the docstring's stated REASON survive recursion? ----
    # The docstring picks `iterdir()` over `rglob()` so `__pycache__` is not descended into.
    # Test that claim directly: does a RECURSIVE walk that prunes `__pycache__` see the same set?
    emit("REASON", "pycache_on_disk", sorted(
        str(p.relative_to(ROOT)) for h in gp.HOMES for p in (ROOT / h).glob("__pycache__/*.pyc")))
    emit("REASON", "pycache_seen_by_walk", sorted(r for r in walk if "__pycache__" in r))
    emit("REASON", "pycache_in_disc", sorted(r for r in disc if "__pycache__" in r))

    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()