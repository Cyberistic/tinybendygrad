#!/usr/bin/env python3
"""Census of UNSORTED ITERATION that can reach a graphcmp artifact, in `runs/graphcmp/D`.

POPULATION BY DISCOVERY, NOT A HAND LIST. The artifact-producing scripts are the string
literals `checks/differ.py` itself hands to a subprocess (`capture(...)`, `run(...)`, the
`PY`/`GCMP` constants); a script the driver stops running leaves the census instead of
rotting in it. The historical offender -- `graphcmp-oracle.py`'s bare `{py['ops'] ^
bd['ops']}` -- is the reason this exists: it made `D0-coverage-census.txt` differ between two
runs of the same tree (commit 46c52f30d sorted it).

A WRITE SITE is a `print(...)` or a `write*` call: a statement that emits bytes into an
artifact stream. A site is a CANDIDATE when an order-bearing subexpression reaches its output
and nothing in the site wraps it in `sorted(...)`. Candidates are VETTED by hand; the census
reports both, so a false positive is visible and not counted as clean.

    .venv/bin/python .agents/slop/reprofix/census.py
"""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIFFER = ROOT / "checks/differ.py"

SET_CALLS = {"set", "frozenset", "Counter", "dir", "glob", "listdir"}
SET_ATTRS = {"items", "keys", "values"}
SET_OPS = {ast.BitXor, ast.BitOr, ast.BitAnd}


def declared_scripts() -> list[Path]:
    """What `differ.py` runs, from its own source: every `.py` literal plus `PY`/`GCMP`."""
    src = DIFFER.read_text()
    names = set(re.findall(r'"([^"]+\.(?:py|bend|sh))"', src))
    names |= set(re.findall(r"'([^']+\.(?:py|bend|sh))'", src))
    for m in re.finditer(r"^\s*(?:PY|GCMP)\s*=\s*\"([^\"]+)\"", src, re.M):
        names.add(m.group(1))
    return [ROOT / n for n in sorted(names) if (ROOT / n).suffix == ".py" and (ROOT / n).exists()]


def parents(tree: ast.AST) -> dict[ast.AST, ast.AST]:
    p = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            p[child] = node
    return p


def emit_sites(tree: ast.AST):
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            f = node.func
            name = f.id if isinstance(f, ast.Name) else getattr(f, "attr", "")
            if name in ("print", "write", "write_text", "write_bytes", "writelines"):
                yield node


def order_bearing(node: ast.AST) -> str | None:
    """The name of the order-bearing construct this expression IS, if any."""
    if isinstance(node, ast.Set):
        return "set-literal"
    if isinstance(node, ast.SetComp):
        return "set-comprehension"
    if isinstance(node, ast.DictComp):
        return "dict-comprehension"
    if isinstance(node, ast.Call):
        f = node.func
        name = f.id if isinstance(f, ast.Name) else getattr(f, "attr", "")
        if name in SET_CALLS:
            return f"{name}()"
        if name in SET_ATTRS:
            return f".{name}()"
    if isinstance(node, ast.BinOp) and type(node.op) in SET_OPS:
        return "set-operator"
    return None


def guarded(node: ast.AST, par: dict[ast.AST, ast.AST]) -> bool:
    """True when an ancestor is `sorted(...)`, `set(...)`-for-membership, `len(...)`, or a
    comparison -- i.e. the ORDER of this value cannot reach the output."""
    cur = node
    while cur in par:
        cur = par[cur]
        if isinstance(cur, ast.Call):
            f = cur.func
            name = f.id if isinstance(f, ast.Name) else getattr(f, "attr", "")
            if name in ("sorted", "len", "any", "all", "sum", "min", "max"):
                return True
        if isinstance(cur, ast.Compare):
            return True
    return False


def name_bound_order_bearing(tree: ast.AST, par: dict[ast.AST, ast.AST]) -> set[str]:
    """Names assigned from an order-bearing expression. The historical offender binds the
    set render to `same = f"... {py['ops'] ^ bd['ops']}"` and prints `same` LATER, so a
    detector that only inspects the emit site's own AST misses it -- this closes that gap the
    same way `p13-ops.py`'s `same` reached `print`. FLOW-INSENSITIVE and over-flagging: a name
    assigned anywhere is treated as order-bearing at every later use, and vetting removes the
    false positives."""
    out: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value is not None:
            if any((m := order_bearing(sub)) and not guarded(sub, par)
                   for sub in ast.walk(node.value)):
                tgts = node.targets if isinstance(node, ast.Assign) else [node.target]
                out |= {t.id for t in tgts if isinstance(t, ast.Name)}
    return out


def main() -> int:
    sites = candidates = 0
    found = []
    scripts = declared_scripts()
    for path in scripts:
        src = path.read_text()
        tree = ast.parse(src)
        par = parents(tree)
        bound = name_bound_order_bearing(tree, par)
        rel = path.relative_to(ROOT).as_posix()
        for node in emit_sites(tree):
            sites += 1
            hits = {m for sub in ast.walk(node)
                    if (m := order_bearing(sub)) and not guarded(sub, par)}
            hits |= {f"via name {n.id}" for n in ast.walk(node)
                     if isinstance(n, ast.Name) and n.id in bound and not guarded(n, par)}
            if hits:
                candidates += 1
                seg = " ".join((ast.get_source_segment(src, node) or "").split())
                found.append((rel, node.lineno, sorted(hits), seg))
    print(f"population = {len(scripts)} artifact-producing scripts, declared by checks/differ.py")
    for p in scripts:
        print(f"  {p.relative_to(ROOT).as_posix()}")
    print(f"write sites  = {sites}")
    print(f"CANDIDATES   = {candidates} (order-bearing, unsorted -- to be vetted)")
    print(f"clean        = {sites - candidates}")
    for rel, ln, hits, seg in found:
        print(f"  CANDIDATE {rel}:{ln} {hits}")
        print(f"      {seg[:170]}")
    return 1 if candidates else 0


if __name__ == "__main__":
    sys.exit(main())
