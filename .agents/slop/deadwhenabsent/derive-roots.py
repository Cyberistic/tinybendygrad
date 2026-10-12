#!/usr/bin/env python3
"""Can RESIDUE_ROOTS be DERIVED from the tree's own write sites, the way HOMES and ROOTS were?

The claim under test: `checks/sweep.py:72 RESIDUE_ROOTS = (".agents/slop", "runs")` is a hand list of
TWO names, and it is the second hand list in that file after the `LIVE_UNITS` tuple of 14 that held
53% of `.slop`. A derivation that reproduces the same two names from a population the tree itself
declares would be a population by doctrine 1(c) -- a walk over the tree's own WRITE SITES.

Three candidate derivations, measured, because only one of them is allowed to be the answer:

  A  write sites, top-level component      -- what instruments WRITE into
  B  A, minus anything git tracks          -- what the sweep may actually DESTROY
  C  A, minus tracked, minus gitignored    -- the guess, and it is wrong by construction:
                                               `runs/` IS gitignored, so C drops the exact
                                               directory this unit is about

usage: .venv/bin/python .agents/slop/deadwhenabsent/derive-roots.py
"""
from __future__ import annotations

import ast
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
WRITES = {"makedirs", "mkdir", "write_text", "write_bytes", "open", "touch", "mkstemp", "NamedTemporaryFile"}


def const(node, env, depth=0):
    if depth > 6:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.Attribute):
        return const(node.value, env, depth + 1)
    if isinstance(node, ast.BinOp):
        # `ast.Div` IS `Path.__truediv__`, and it is the DOMINANT idiom: MEASURED, **732**
        # `BinOp(Div)` joins across `checks/*.py` + `gates/*.py`, against a handful of
        # `os.path.join` calls. `checks/sweep.py:140-153`'s own `const()` handles `Add` and
        # `Call(join)` and NOT `Div`, which is why `self_output_dirs()` answers **1** directory
        # on a tree with 187 instruments. **A RESOLVER THAT UNDERSTANDS ONE SPELLING OF A PATH
        # FINDS NOTHING, AND AN INSTRUMENT THAT FINDS NOTHING CANNOT BE A POPULATION.**
        if not isinstance(node.op, (ast.Add, ast.Div)):
            return None
        a, b = const(node.left, env, depth + 1), const(node.right, env, depth + 1)
        if isinstance(a, str) and isinstance(b, str):
            return os.path.join(a, b) if isinstance(node.op, ast.Div) else a + b
        if isinstance(node.op, ast.Div) and isinstance(b, str) and isinstance(a, str):
            return os.path.join(a, b)
        return None
    if isinstance(node, ast.Subscript):
        # `Path(__file__).resolve().parents[1]` -- `parents[n]` is a SUBSCRIPT over a Call, not a
        # Call with an `.n`. MEASURED: getting this wrong makes `ROOT` unresolvable, which makes
        # every path `../<top>` and every top `.`, which filters to ZERO and reads as a clean
        # answer. **FOUR OF MY OWN MEASUREMENTS IN THIS UNIT FAILED THIS WAY.**
        base = const(node.value, env, depth + 1)
        if isinstance(base, str) and isinstance(node.slice, ast.Constant) and isinstance(node.slice.value, int):
            return "/".join([".."] * node.slice.value)
        return None
    if isinstance(node, ast.Call):
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if fn in ("join", "as_posix"):
            parts = [const(a, env, depth + 1) for a in node.args]
            if any(p for p in parts):
                return os.path.join(*(p if isinstance(p, str) else "?" for p in parts))
        if fn in ("resolve", "absolute", "realpath", "expanduser"):
            return const(node.func.value, env, depth + 1) if isinstance(node.func, ast.Attribute) else None
        if fn == "Path":
            return ""
    return None


def head_of(path: str) -> str | None:
    """The first component that is not `.` and not `..` -- the top-level directory a path names.

    `ROOT` resolves to `..` or `../..`, so a resolved path is RELATIVE and begins with `..`. A
    resolver that takes `split("/")[0]` of `../runs/graphcmp/D` gets `..` and concludes the tree
    writes nowhere, which is the SAME clean zero as four bugs ago and would have been believed.
    """
    for part in path.split("/"):
        if part in ("", ".", ".."):
            continue
        return part
    return None


def write_targets(root: str) -> dict[str, set[str]]:
    """top-level component -> the repo-relative paths instruments WRITE into it."""
    hits: dict[str, set[str]] = {}
    for path in sorted(glob.glob(os.path.join(root, "checks", "*.py"))
                       + glob.glob(os.path.join(root, "gates", "*.py"))):
        try:
            tree = ast.parse(open(path, errors="replace").read())
        except (OSError, SyntaxError):
            continue
        env: dict[str, str] = {}
        for _ in range(4):  # module-level bindings, resolved to a fixed point
            for st in tree.body:
                if isinstance(st, ast.Assign) and len(st.targets) == 1 and isinstance(st.targets[0], ast.Name):
                    if (v := const(st.value, env)) is not None:
                        env[st.targets[0].id] = v
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            if fn not in WRITES:
                continue
            if fn == "open" and not (
                len(node.args) > 1 and isinstance(node.args[1], ast.Constant)
                and any(c in str(node.args[1].value) for c in "wax+")
            ):
                continue
            # **A `pathlib` WRITE SITE IS THE RECEIVER, NOT AN ARGUMENT.** `D.write_text(s)` names
            # the directory in `node.func.value`; `node.args` holds the CONTENT. `checks/sweep.py:182`
            # iterates `list(node.args) + [k.value for k in node.keywords]` -- arguments only -- so
            # it cannot see a single `pathlib` write even once it understands `Div`. TWO INDEPENDENT
            # BLIND SPOTS, and fixing either one alone still returns 1 directory.
            sites = list(node.args) + [k.value for k in node.keywords]
            if isinstance(node.func, ast.Attribute):
                sites.append(node.func.value)
            for arg in sites:
                v = const(arg, env)
                if not v or not isinstance(v, str):
                    continue
                head = head_of(v)
                if head and os.path.isdir(os.path.join(root, head)):
                    hits.setdefault(head, set()).add(os.path.relpath(path, root))
    return hits


def tracked(root: str) -> set[str]:
    r = subprocess.run(["git", "-C", root, "ls-tree", "-r", "--name-only", "HEAD"],
                       capture_output=True, text=True)
    return {line.split("/", 1)[0] for line in r.stdout.splitlines() if line}


def ignored(root: str, head: str) -> bool:
    r = subprocess.run(["git", "-C", root, "check-ignore", "-q", head], capture_output=True, text=True)
    return r.returncode == 0


def main() -> int:
    targets = write_targets(ROOT)
    tr = tracked(ROOT)
    print("top-level dirs an instrument WRITES into (from AST write sites in checks/ + gates/):")
    for head in sorted(targets):
        print(f"  {head:<24} tracked={'Y' if head in tr else 'n':<2} "
              f"ignored={'Y' if ignored(ROOT, head) else 'n':<2} writers={len(targets[head])}")
    a = set(targets)
    b = {h for h in a if h not in tr}
    c = {h for h in b if not ignored(ROOT, h)}
    print()
    print(f"A  write sites, top-level          : {len(a):>2}  {sorted(a)}")
    print(f"B  A minus git-tracked             : {len(b):>2}  {sorted(b)}")
    print(f"C  B minus gitignored              : {len(c):>2}  {sorted(c)}   <- DROPS runs/, by construction")
    print()
    declared = (".agents/slop", "runs")
    print(f"the HAND LIST at sweep.py:72       : {len(declared):>2}  {sorted(declared)}")
    for name, cand in (("A", a), ("B", b), ("C", c)):
        print(f"  {name} == hand list ? {cand == set(declared)}   "
              f"extra={sorted(cand - set(declared))}  missing={sorted(set(declared) - cand)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
