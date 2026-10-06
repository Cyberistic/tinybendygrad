#!/usr/bin/env python3
"""Discovery + signal dump over the two gate homes. NO execution, no side effects.

Population = iterdir of checks/ and gates/, `.py`/`.sh` only. An entry point is a Python
file whose AST holds an `if __name__` guard, or a shell file that self-references `$0`.
Every other file is a LIB (a module a gate imports). Read-only.
"""
from __future__ import annotations
import ast
import io
import re
import sys
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HOMES = ("checks", "gates")
SUFFIXES = (".py", ".sh")

SH_ENTRANCE = re.compile(r"^\s*(?:exec\b|\$\{?0)", re.M)
SH_SELFREF = re.compile(r"\$\{?0\b")
SH_COMMENT = re.compile(r"^\s*#.*$", re.M)


def strip_comments(src):
    """Drop `#` comments and blank DOCSTRINGS, so prose is never read as code."""
    try:
        docs = set()
        for node in ast.walk(ast.parse(src)):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef,
                                 ast.AsyncFunctionDef)):
                d = ast.get_docstring(node, clean=False)
                if d is not None:
                    ex = node.body[0]
                    docs.update(range(ex.lineno, (ex.end_lineno or ex.lineno) + 1))
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (SyntaxError, tokenize.TokenError, IndentationError):
        return src
    out = []
    for t in toks:
        if t.type == tokenize.COMMENT:
            out.append(t._replace(string=""))
        elif t.type == tokenize.STRING and t.start[0] in docs:
            out.append(t._replace(string=t.string[0] + " " * (len(t.string) - 2) + t.string[-1]))
        else:
            out.append(t)
    return tokenize.untokenize(out)


def is_py_entry(src):
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return f"UNPARSEABLE({e.msg}@{e.lineno})"
    return any(isinstance(n, ast.If) and "__main__" in ast.dump(n.test)
               for n in ast.walk(tree))


def is_sh_entry(src):
    s = SH_COMMENT.sub("", src)
    return bool(SH_ENTRANCE.search(s) or SH_SELFREF.search(s))


def imports(src, name):
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            if any(a.name.split(".")[0] == name for a in n.names):
                return True
        elif isinstance(n, ast.ImportFrom):
            mod = (n.module or "").split(".")[0]
            if mod == name:
                return True
    return False


def signals(p):
    raw = p.read_text(errors="replace")
    code = strip_comments(raw) if p.suffix == ".py" else SH_COMMENT.sub("", raw)
    return {
        "py_entry": (is_py_entry(raw) is True) if p.suffix == ".py" else False,
        "sh_entry": is_sh_entry(raw) if p.suffix == ".sh" else False,
        "gatekit": imports(raw, "gatekit") if p.suffix == ".py" else False,
        "ascii_art": False,
        "bend": bool(re.search(r"\bbend\b", code)),
        "argparse": bool(re.search(r"\bargparse\b", code)),
        "subprocess": bool(re.search(r"\bsubprocess\b", code)),
        "tinygrad": imports(raw, "tinygrad") or imports(raw, "common"),
        "write_src": bool(re.search(r"\.bend\b", code)) and bool(
            re.search(r"write_text|write_bytes|open\([^)]*[\"'](?:w|a)", code)),
        "exit3": bool(re.search(r"exit\s*\(\s*3|SystemExit\s*\(\s*3", code)),
        "rows_print": len(re.findall(r"print\(.*?[=:].*?\)", code)),
    }


def main():
    rows = []
    libs = []
    for home in HOMES:
        h = ROOT / home
        for p in sorted(h.iterdir()):
            if p.suffix not in SUFFIXES or not p.is_file():
                continue
            s = signals(p)
            entry = s["py_entry"] or s["sh_entry"]
            (rows if entry else libs).append((str(p.relative_to(ROOT)), s))
    print(f"ENTRY POINTS: {len(rows)}   LIBS (no guard): {len(libs)}")
    print(f"{'path':48} {'gk':>2} {'bend':>4} {'arg':>3} {'sub':>3} {'tgr':>3} {'wrt':>3} {'e3':>2} rows")
    for path, s in rows:
        print(f"{path:48} {int(s['gatekit']):>2} {int(s['bend']):>4} {int(s['argparse']):>3} "
              f"{int(s['subprocess']):>3} {int(s['tinygrad']):>3} {int(s['write_src']):>3} "
              f"{int(s['exit3']):>2} {s['rows_print']}")
    print("\nLIBS:", ", ".join(p for p, _ in libs))


if __name__ == "__main__":
    sys.exit(main())
