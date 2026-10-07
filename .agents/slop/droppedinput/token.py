#!/usr/bin/env python3
"""Does a file EMIT a token, or merely MENTION it?

The first version of `twolists.py` tested `"ABSENT" in src` and got `True` for `snapshot.py`.
That is a classifier error of exactly the kind this project keeps measuring: `snapshot.py`'s
ABSENT appears in a DOCSTRING and in `--declare`'s own print string, and in NEITHER is it a value
that reaches a population row. A mention is not an emission, and a grep cannot tell them apart.

This asks the question at the AST level, per occurrence: is the string `ABSENT` a
  * `Constant` inside an `Expr` statement  -> a docstring (or a bare string statement)
  * a `#` comment                      -> not in the tree at all
  * any other `Constant`                -> it IS an emitted value

    usage: .venv/bin/python .agents/slop/droppedinput/token.py FILE [FILE ...]
"""
from __future__ import annotations

import ast
import pathlib
import sys

TOKEN = "ABSENT"


def occurrences(path: pathlib.Path) -> list[tuple[int, str]]:
    """(lineno, kind) for every TOKEN in the file: `value`, `docstring`, or `comment`."""
    src = path.read_text()
    tree = ast.parse(src)
    doc_lines: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and \
                isinstance(node.value.value, str):
            doc_lines.update(range(node.lineno, (node.end_lineno or node.lineno) + 1))
    out: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and node.value in (TOKEN, TOKEN.encode()) and \
                node.lineno not in doc_lines:
            out.append((node.lineno, "value"))
    for i, ln in enumerate(src.splitlines(), 1):
        stripped = ln.strip()
        if TOKEN in ln and not stripped.startswith("#") and i not in doc_lines:
            # a bare occurrence in code that AST did not see as a standalone value: a substring
            # of a larger string, or an f-string piece. Named, so the row is honest about it.
            if not any(ln_no == i for ln_no, _ in out):
                out.append((i, "in-expression"))
    for i, ln in enumerate(src.splitlines(), 1):
        if TOKEN in ln and ln.strip().startswith("#"):
            out.append((i, "comment"))
    return sorted(set(out))


def main() -> int:
    rc = 0
    for arg in sys.argv[1:]:
        p = pathlib.Path(arg)
        occ = occurrences(p)
        n_val = sum(1 for _, k in occ if k == "value")
        print(f"{p}")
        for ln, kind in occ:
            print(f"  {kind:<14} :{ln}")
        print(f"  TOTAL {len(occ)}  EMITTED-VALUES {n_val}")
        if n_val == 0:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())