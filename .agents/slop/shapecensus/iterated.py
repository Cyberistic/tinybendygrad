#!/usr/bin/env python3
"""Narrow `signals.rows` to the LISTS and GLOBS that are actually ITERATED, and print the
iteration site beside the binding site. A literal nobody loops over is a value, not a population.

usage: .venv/bin/python .agents/slop/shapecensus/iterated.py [home]
"""
from __future__ import annotations

import ast
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HOMES = ("checks", "gates")


def str_container(node: ast.AST) -> bool:
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        return all(str_container(e) for e in node.elts) and bool(node.elts)
    if isinstance(node, ast.Dict):
        return all(isinstance(k, ast.Constant) and isinstance(k.value, str) for k in node.keys)
    return isinstance(node, ast.Constant) and isinstance(node.value, str)


def mod_literals(tree: ast.Module) -> dict[str, tuple[int, str, ast.AST]]:
    out = {}
    for n in tree.body:
        ts = []
        if isinstance(n, ast.Assign):
            ts = n.targets
        elif isinstance(n, ast.AnnAssign) and n.value is not None:
            ts = [n.target]
        for t in ts:
            if isinstance(t, ast.Name) and n.value is not None and str_container(n.value):
                out[t.id] = (n.lineno, ast.unparse(n.value).replace("\n", " "), n.value)
    return out


def iterated(tree: ast.Module) -> list[tuple[str, int]]:
    out = []
    for n in ast.walk(tree):
        it = None
        if isinstance(n, (ast.For, ast.AsyncFor)):
            it = n.iter
        elif isinstance(n, ast.comprehension):
            it = n.iter
        if it is None:
            continue
        if isinstance(it, ast.Name):
            out.append((it.id, getattr(n, "lineno", 0)))
        elif isinstance(it, (ast.ListComp, ast.SetComp, ast.GeneratorExp, ast.DictComp)):
            for sub in ast.walk(it.elt) if hasattr(it, "elt") else []:
                if isinstance(sub, ast.Name):
                    out.append((sub.id, getattr(sub, "lineno", 0)))
    return out


def main() -> int:
    homes = (sys.argv[1],) if len(sys.argv) > 1 else HOMES
    for home in homes:
        for p in sorted((ROOT / home).rglob("*.py")):
            rel = p.relative_to(ROOT)
            try:
                tree = ast.parse(p.read_text(encoding="utf-8", errors="replace"))
            except SyntaxError:
                continue
            lits = mod_literals(tree)
            if not lits:
                continue
            used: dict[str, list[int]] = {}
            for name, ln in iterated(tree):
                if name in lits:
                    used.setdefault(name, []).append(ln)
            for name, lines in sorted(used.items()):
                ln, text, _ = lits[name]
                print(f"{rel}\tSTR-LIST\t{name}\tbind:{ln}\titer:{','.join(map(str, lines))}\t{text[:130]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())