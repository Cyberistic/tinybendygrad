#!/usr/bin/env python3
"""The OTHER structural shape: a gate that reads `sys.argv[i]` with NO length guard.

`checks/oracle_f64.py:266` reads `sys.argv[1]` inside `main()` and answers `IndexError`, rc=1 --
so its only reachable state is a TRACEBACK, which the project's own definition is neither `FAIL`
nor `DEAD` but is certainly not a verdict. **A traceback carries no denominator and counts
nowhere** (`checks/census.py`'s docstring says this verbatim).

THE SHAPE, DISCOVERED: `sys.argv[N]` is a SUBSCRIPT on `sys.argv` whose index is an integer
literal above 0. A slice, a `len()` guard in the same expression, and any name other than `argv`
are excluded -- a negative filter, and the filter is named here because `repro-paths.py`'s REF is
the measured instance of a rule that could not see a file that exists.

    .venv/bin/python .agents/slop/modulerefuse/argv.py
"""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def def_spans(tree):
    return [(n.lineno, n.end_lineno or n.lineno)
            for n in ast.walk(tree)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda))]


def guarded(tree, line):
    """True if any `len(sys.argv)` comparison appears within 6 lines above. A NEGATIVE filter that
    is also a MEASUREMENT would be better, so this is stated as the limit it is."""
    src = ast.unparse(tree).splitlines()
    for i, l in enumerate(src, 1):
        if abs(i - line) <= 6 and "len(sys.argv)" in l:
            return True
    return False


def main():
    hits = []
    for home in ("checks", "gates"):
        h = ROOT / home
        if not h.is_dir():
            continue
        for p in sorted(h.iterdir()):
            if p.suffix != ".py" or not p.is_file():
                continue
            try:
                tree = ast.parse(p.read_text(errors="replace"))
            except SyntaxError:
                continue
            spans = def_spans(tree)
            for n in ast.walk(tree):
                if not (isinstance(n, ast.Subscript) and isinstance(n.value, ast.Attribute)
                        and n.value.attr == "argv"):
                    continue
                sl = n.slice
                if not (isinstance(sl, ast.Constant) and isinstance(sl.value, int)
                        and sl.value > 0):
                    continue
                in_def = any(lo <= n.lineno <= hi for lo, hi in spans)
                hits.append((str(p.relative_to(ROOT)), n.lineno, sl.value, in_def,
                             guarded(tree, n.lineno)))
    print(f"DISCOVERED {len(hits)} unguarded `sys.argv[N]` read(s), N>0, across checks/ and "
          f"gates/\n")
    print(f"{'file':38} {'line':>5} {'argv':>5} {'in def':>7} {'len-guard':>10}")
    for rel, ln, n, indef, g in hits:
        print(f"{rel:38} {ln:>5} argv[{n}] {'yes' if indef else 'MODULE':>7} "
              f"{'near' if g else 'NONE':>10}")
    return 0


if __name__ == "__main__":
    sys.exit(main())