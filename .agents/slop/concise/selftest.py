#!/usr/bin/env python3
"""Two checks on census.py itself, because an instrument that cannot be wrong
cannot be anything (AGENTS.md doctrine 1).

CHECK 1 -- does the .bend lexer see what grep sees? `grep -c '#'` counts a `#`
inside a string literal. tinybendygrad/sz.bend:1547 holds "### Changes\\n```\\n"
in a real string, so the two MUST disagree and the gap IS the measurement.

CHECK 2 -- is the Python docstring counter counting docstrings? It counts a
STRING token as a docstring when a `def`/`class` keyword was the last
significant token. That rule is WRONG for `def f() -> "Ret":`, where the string
is a return ANNOTATION. Printed per-file, so a wrong file is nameable.
"""

import ast
import io
import os
import subprocess
import sys
import tokenize

sys.path.insert(0, os.path.dirname(__file__))
from census import bend_lex, py_rows, tracked, walk  # noqa: E402


def check_bend() -> None:
    print("CHECK 1  .bend: lexer vs `grep -c '#'`")
    print(f"  {'file':<52} {'lexer':>6} {'grep':>6} {'delta':>6}")
    tot_lex = tot_grep = 0
    gaps = []
    for path in sorted(tracked() & walk()):
        if not path.endswith(".bend"):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        lex = sum(1 for line in src.splitlines() if bend_lex(line))
        grep = int(subprocess.run(["grep", "-c", "#", path],
                                  capture_output=True, text=True).stdout or 0)
        tot_lex += lex
        tot_grep += grep
        if lex != grep:
            gaps.append((path, lex, grep))
    print(f"  {'TOTAL over the .bend population':<52} {tot_lex:>6} {tot_grep:>6} "
          f"{tot_grep - tot_lex:>+6}")
    print(f"  files where they differ: {len(gaps)}")
    for path, lex, grep in gaps[:8]:
        print(f"  {path:<52} {lex:>6} {grep:>6} {grep - lex:>+6}")


def check_docstring() -> None:
    print("\nCHECK 2  .py: docstring counter vs `ast`")
    print("  ast counts a docstring ONLY when the STRING is the sole stmt of a")
    print("  Module/FunctionDef/ClassDef body. The tokenizer heuristic also fires")
    print("  on `def f() -> \"Ret\":` and on any module-level bare string.")
    over = []
    t_lex = a_lex = 0
    for path in sorted(tracked() & walk()):
        if not path.endswith(".py"):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        _, doc, err = py_rows(src)
        if err or doc == 0:
            continue
        try:
            tree = ast.parse(src)
        except SyntaxError:
            continue
        real = sum(len(ast.get_docstring(n, clean=False).splitlines())
                   for n in ast.walk(tree)
                   if isinstance(n, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                                     ast.ClassDef)) and ast.get_docstring(n, clean=False))
        t_lex += doc
        a_lex += real
        if doc != real:
            over.append((path, doc, real))
    print(f"  {'TOTAL docstring lines, tokenizer heuristic':<52} {t_lex:>6}")
    print(f"  {'TOTAL docstring lines, ast.get_docstring':<52} {a_lex:>6}")
    print(f"  {'OVERCOUNT':<52} {t_lex - a_lex:>+6}")
    print(f"  files where they differ: {len(over)}")
    for path, doc, real in sorted(over, key=lambda r: -(r[1] - r[2]))[:8]:
        print(f"  {path:<52} tok={doc:<5} ast={real:<5} +{doc - real}")


if __name__ == "__main__":
    check_bend()
    check_docstring()
    sys.exit(0)
