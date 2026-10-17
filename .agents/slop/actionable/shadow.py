#!/usr/bin/env python3
"""SHADOW USE: for each ACTIONABLE path, find CODE lines in its citing instruments that reference the
path WITHOUT spelling it out -- via a variable holding its directory, or its basename.  The literal
match in `checks/repro-paths.py` sees only the spelled-out name, so a gate that does
`D=.agents/slop/x; ORACLE=$D/oracle.py` is invisible to it while being very much a live user.

Parses source text with `ast`/`tokenize`; imports nothing from the repo; executes none of it."""
from __future__ import annotations

import ast
import io
import os
import re
import sys
import tokenize

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
HERE = os.path.join(ROOT, ".agents/slop/actionable")
SHELL_NOISE = re.compile(r"^\s*#|^\s*$")


def parse_rows() -> list[tuple[str, list[str]]]:
    rows = []
    for line in open(os.path.join(HERE, "run.out"), encoding="utf-8"):
        m = re.match(r"\s*ACTIONABLE (\S+)\s+<- (.*)$", line.rstrip("\n"))
        if m:
            rows.append((m.group(1), [c.strip() for c in m.group(2).split(",")]))
    return rows


def dead_lines(src: str, is_py: bool) -> set[int]:
    """Lines that are PROSE, so a mention there is not a use.

    ONLY two things are prose: `#` comments, and a docstring -- the FIRST statement of a module,
    class or function.  **Everything else that is a string literal is CODE, and retiring it hid the
    use.**  `_live = HERE / "nl-port-post.txt"` is a string literal, and it is the exact line that
    makes `checks/nl-port-post.txt` a real input to `checks/nl-gate.py`; the first version of this
    scanner retired every STRING token, reported "no live code line names the basename", and would
    have filed that row as prose because the only FULL-PATH mention in the file is a comment four
    lines below the guard.  A gate writes its inputs as string literals -- that is what an argv and
    a Path() are made of."""
    out: set[int] = set()
    if not is_py:
        return {i for i, line in enumerate(src.splitlines(), 1)
                if line.lstrip().startswith("#")}
    try:
        for tok in tokenize.generate_tokens(io.StringIO(src).readline):
            if tok.type == tokenize.COMMENT:
                out.add(tok.start[0])
    except Exception:
        return {i for i, line in enumerate(src.splitlines(), 1)
                if line.lstrip().startswith("#")}
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return out
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            body = getattr(node, "body", None)
            if body and isinstance(body[0], ast.Expr) \
                    and isinstance(body[0].value, ast.Constant) \
                    and isinstance(body[0].value.value, str):
                out |= set(range(body[0].lineno,
                                 (body[0].value.end_lineno or body[0].lineno) + 1))
    return out


def main() -> int:
    out = []
    for path, citers in parse_rows():
        base = os.path.basename(path)
        dirs = {os.path.dirname(path)} - {""}
        out.append(f"=== PATH {path}")
        for rel in citers:
            fp = os.path.join(ROOT, rel)
            if not os.path.isfile(fp):
                continue
            src = open(fp, encoding="utf-8", errors="replace").read()
            dead = dead_lines(src, rel.endswith(".py"))
            hits = []
            for i, line in enumerate(src.splitlines(), 1):
                if i in dead or SHELL_NOISE.match(line):
                    continue
                if base in line or any(d and d in line for d in dirs):
                    hits.append(f"    L{i:<5} {line.strip()[:190]}")
            out.append(f"  CITER {rel}")
            out.extend(hits or ["    (no live code line names the basename or its directory)"])
    open(os.path.join(HERE, "shadow.rows"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"lines={len(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())