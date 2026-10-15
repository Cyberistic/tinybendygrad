#!/usr/bin/env python3
"""Extract the MEMBERSHIP-DEFINING EXPRESSION of every `*.py` under `checks/` and `gates/`.

The population is DISCOVERED: `rglob("*.py")` over the two directories, no list from any document.
Read-only over the tree; writes one `.rows` file and nothing else.

WHAT IS EXTRACTED, per file:
  walk     `os.walk` / `rglob` / `iterdir` / `os.scandir` / `os.listdir` -- a DIRECTORY WALK
  glob     `glob` / `iglob` / `Path.glob` -- a GLOB, which is a set of names this file chooses
  strlit   a literal container of strings bound to a name -- a HAND LIST
  endswith `.endswith` / `.startswith` with a literal tuple -- a SUFFIX SET
  regex    `re.compile`/`findall`/`finditer`/`search`/`match` -- a SHAPE, or a write-site scan

usage: .venv/bin/python .agents/slop/shapecensus/extract.py > .agents/slop/shapecensus/signals.rows
"""
from __future__ import annotations

import ast
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HOMES = ("checks", "gates")

WALK_FNS = {"walk", "rglob", "iterdir", "scandir", "listdir", "walkdir"}
GLOB_FNS = {"glob", "iglob"}


def src(node: ast.AST) -> str:
    return ast.unparse(node).replace("\n", " ")[:160]


def is_str_container(node: ast.AST) -> bool:
    """A literal container holding nothing but strings (nested containers count)."""
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        return all(is_str_container(e) for e in node.elts) and bool(node.elts)
    if isinstance(node, ast.Dict):
        return all(isinstance(k, ast.Constant) and isinstance(k.value, str) for k in node.keys)
    return isinstance(node, ast.Constant) and isinstance(node.value, str)


def callee(node: ast.Call) -> str:
    f = node.func
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return ""


def walk_calls(node: ast.AST) -> list[tuple[str, int, str]]:
    out = []
    for n in ast.walk(node):
        if not isinstance(n, ast.Call):
            continue
        name = callee(n)
        if name in WALK_FNS:
            out.append(("walk", n.lineno, src(n)))
        elif name in GLOB_FNS:
            out.append(("glob", n.lineno, src(n)))
    return out


def literal_lists(tree: ast.Module) -> list[tuple[str, int, str]]:
    out = []
    for n in tree.body:                      # module level ONLY: a local literal is a value
        targets = []
        if isinstance(n, ast.Assign):
            targets = n.targets
        elif isinstance(n, ast.AnnAssign) and n.value is not None:
            targets = [n.target]
        for t in targets:
            if isinstance(t, ast.Name) and n.value is not None and is_str_container(n.value):
                out.append((t.id, n.lineno, src(n.value)))
    return out


def endswith(tree: ast.Module) -> list[tuple[str, int, str]]:
    out = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and callee(n) in ("endswith", "startswith") and n.args:
            if is_str_container(n.args[0]):
                out.append((callee(n), n.lineno, src(n.args[0])))
    return out


def regexes(tree: ast.Module) -> list[tuple[str, int, str]]:
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        c = callee(n)
        if c == "compile" and n.args:
            out.append(("re.compile", n.lineno, src(n.args[0])))
        elif c in ("findall", "finditer", "search", "match", "fullmatch") and n.args:
            out.append((f"re.{c}", n.lineno, src(n.args[0])))
    return out


def iters(tree: ast.Module) -> list[tuple[int, str]]:
    out = []
    for n in ast.walk(tree):
        if isinstance(n, (ast.For, ast.AsyncFor)):
            out.append((n.lineno, src(n.iter)))
        elif isinstance(n, ast.comprehension):
            out.append((getattr(n, "lineno", 0), src(n.iter)))
    return out


def main() -> int:
    rows = []
    for home in HOMES:
        for p in sorted((ROOT / home).rglob("*.py")):
            rel = p.relative_to(ROOT)
            try:
                tree = ast.parse(p.read_text(encoding="utf-8", errors="replace"))
            except SyntaxError as e:
                rows.append((str(rel), "PARSE-ERROR", "none", f"{e.lineno}", str(e.msg)))
                continue
            sig = list(walk_calls(tree))
            sig += [("strlit", ln, f"{n} = {v}") for n, ln, v in literal_lists(tree)]
            sig += [(f"{k}", ln, v) for k, ln, v in endswith(tree)]
            sig += [(k, ln, v) for k, ln, v in regexes(tree)]
            if not sig:
                rows.append((str(rel), "NO-SIGNAL", "none", "0", ""))
                continue
            for k, ln, v in sig:
                rows.append((str(rel), k, v.replace("\t", " "), str(ln), ""))
    for r in rows:
        print("\t".join(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())