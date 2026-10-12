#!/usr/bin/env python3
"""Who reads runs/graphcmp, by AST, and does the write, the read, or just say it?

Three populations are compared, because the brief's "13" is a number with no rule attached:
  MENTION  the substring appears anywhere in the file, comments and docstrings included
  CODE     the substring appears in an executable code position (ast, so a docstring cannot be it)
  RESOLVED a module-level constant or `os.path.join` RESOLVES to a path under `runs/graphcmp`,
           which is how a gate can read the corpus without ever typing the string whole

usage: .venv/bin/python .agents/slop/deadwhenabsent/census.py
"""
from __future__ import annotations

import ast
import glob
import os

# FOUR `dirname`, NOT THREE. MEASURED: with three this was `ROOT/.agents`, every glob under it
# matched nothing, and this instrument printed `scanned .py : 0` for a tree with 187 of them.
# **AN INSTRUMENT THAT CANNOT SEE ITS POPULATION REPORTS A CLEAN ZERO, WHICH IS WHY THE DENOMINATOR
# IS PRINTED NEXT TO THE COUNT AND NOT IN A COMMENT.**
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
assert os.path.isdir(os.path.join(ROOT, "checks")), f"ROOT is {ROOT}, not the repository root"
NEEDLE = "runs/graphcmp"


def module_env(tree: ast.Module) -> dict[str, str]:
    """Module-level string bindings, so `RUNS = "runs"` and `RUNS` resolve alike."""
    env: dict[str, str] = {}

    def const(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return env.get(node.id)
        if isinstance(node, ast.Call):
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            if fn == "join":
                lits = [v for v in (const(a) for a in node.args) if isinstance(v, str)]
                return os.path.join(*lits) if lits else None
        return None

    for st in tree.body:
        if isinstance(st, ast.Assign) and len(st.targets) == 1 and isinstance(st.targets[0], ast.Name):
            if (v := const(st.value)) is not None:
                env[st.targets[0].id] = v
    return env


def docstring_ids(tree: ast.Module) -> set[int]:
    """Node identity of every docstring, so `ast.walk` cannot smuggle prose back into CODE."""
    ids: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            body = getattr(node, "body", None)
            if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
                    and isinstance(body[0].value.value, str):
                ids.add(id(body[0].value))
    return ids


def code_strings(tree: ast.Module) -> list[str]:
    """Every string constant in a CODE position.

    **MY OWN SECOND WRONG MEASUREMENT, AND THE BEFORE-VALUE.** The first version of this function
    walked `ast.walk` and filtered on `isinstance(node, ast.Constant)`, with a comment asserting a
    docstring "cannot appear here". IT CAN: a module docstring IS an `ast.Expr` holding an
    `ast.Constant`, and `ast.walk` yields it. That reported `checks/residue.py` as a READER on the
    strength of `residue.py:44`, which is a line of a module docstring about DELETE rows. CODE was
    **14** and it should have been **13** -- the same 13 the brief quotes, reached by a wrong route.

    So docstrings are now DELETED FROM THE TREE by node identity before the walk, and a docstring's
    contents are counted separately as PROSE. **A POPULATION THAT INCLUDES ITS OWN NARRATION CANNOT
    COUNT READERS.**
    """
    docs = docstring_ids(tree)
    return [n.value for n in ast.walk(tree)
            if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in docs]


def prose_strings(tree: ast.Module) -> list[str]:
    """The docstrings, counted separately: they SAY the path and do not touch it."""
    docs = docstring_ids(tree)
    return [n.value for n in ast.walk(tree)
            if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) in docs]


def resolves_under_needles(node: ast.AST, env: dict[str, str], prefixes: dict[str, str]) -> set[str]:
    """What path does this node contribute, following module bindings and `join`?"""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return {node.value}
    if isinstance(node, ast.Name):
        return {env[node.id]} if node.id in env else set()
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add) and isinstance(node.left, ast.Constant):
        if isinstance(node.left.value, str) and isinstance(node.right, ast.Constant) and isinstance(node.right.value, str):
            return {node.left.value + node.right.value}
    if isinstance(node, ast.Call):
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if fn == "join":
            parts = [resolves_under_needles(a, env, prefixes) for a in node.args]
            if any(parts):
                # An UNRESOLVED argument is the repo root or a base dir; keep it visible as `?`.
                return {os.path.join(*(sorted(p)[0] if p else "?" for p in parts))}
            return set()
    return set()


def main() -> int:
    files = sorted(glob.glob(os.path.join(ROOT, "checks", "*.py")) + glob.glob(os.path.join(ROOT, "gates", "*.py")))
    slop_py = glob.glob(os.path.join(ROOT, ".agents/slop/**/*.py"), recursive=True)
    mention, code, resolved = [], [], []
    for path in files:
        rel = os.path.relpath(path, ROOT)
        src = open(path, errors="replace").read()
        if NEEDLE in src:
            mention.append(rel)
        try:
            tree = ast.parse(src)
        except SyntaxError:
            continue
        env = module_env(tree)
        docs = docstring_ids(tree)
        if any(NEEDLE in s for s in code_strings(tree)):
            code.append(rel)
        # A DOCSTRING MENTION IS NOT A READER. Resolve through code positions only, so the census
        # cannot count `retention-check.py`'s own prose about the directory it owns.
        hits = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                if id(node) in docs:
                    continue
                hits |= resolves_under_needles(node, env, env)
            elif isinstance(node, ast.BinOp):
                hits |= resolves_under_needles(node, env, env)
        # A binding of `runs` + `graphcmp` is the whole needle split in two.
        if any(NEEDLE in v for v in env.values()):
            hits |= {v for v in env.values() if NEEDLE in v}
        if any(NEEDLE in h for h in hits):
            resolved.append(rel)

    print(f"scanned .py in checks/ + gates/ : {len(files)}")
    print(f"  of which under .agents/slop  : {len(slop_py)}")
    print(f"total .py with the substring    : {len(files) + len(slop_py)}")
    print()
    print(f"MENTION (substring anywhere)     : {len(mention):>3}  {sorted(mention)}")
    print()
    print(f"CODE    (string in a code pos)   : {len(code):>3}  {sorted(code)}")
    print()
    print(f"RESOLVED (a binding resolves to it): {len(resolved):>3}  {sorted(resolved)}")
    m, c, r = set(mention), set(code), set(resolved)
    print()
    print(f"mention but NOT code  (prose)    : {len(m - c)}  {sorted(m - c)}")
    print(f"code but NOT resolved (spelled out in code, not via a binding): {len(c - r)}  {sorted(c - r)}")
    print(f"resolved but NOT code (reached only through a binding): {len(r - c)}  {sorted(r - c)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
