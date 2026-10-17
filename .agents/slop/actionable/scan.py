#!/usr/bin/env python3
"""Locate every mention of each ACTIONABLE path inside each citing instrument, and label the
SYNTAX it sits in.  Parses source text with `ast`/`tokenize`; imports nothing from the repo and
executes none of it.  READ-ONLY: writes one report, touches no instrument."""
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


def parse_rows() -> list[tuple[str, list[str]]]:
    rows = []
    for line in open(os.path.join(HERE, "run.out"), encoding="utf-8"):
        m = re.match(r"\s*ACTIONABLE (\S+)\s+<- (.*)$", line.rstrip("\n"))
        if m:
            rows.append((m.group(1), [c.strip() for c in m.group(2).split(",")]))
    return rows


def docstring_nodes(tree: ast.AST) -> set[int]:
    out: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            body = getattr(node, "body", None)
            if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
                    and isinstance(body[0].value.value, str):
                out |= span(body[0].value)
    return out


def span(node: ast.AST) -> set[int]:
    """Every physical line a string literal covers, not just its first -- a multi-line docstring is
    PROSE on every one of its lines, and reading only its first is how a triage calls prose 'code'."""
    lo = getattr(node, "lineno", 0)
    hi = getattr(node, "end_lineno", lo) or lo
    return set(range(lo, hi + 1))


def literal_lines(tree: ast.AST) -> set[int]:
    out: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and len(node.value) > 3:
            out |= span(node)
    return out


def dict_key_lines(tree: ast.AST) -> set[int]:
    """Line of each dict whose keys are string constants, and of each such key."""
    out: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Dict):
            for k in node.keys:
                if isinstance(k, ast.Constant) and isinstance(k.value, str):
                    out |= span(k)
    return out


def literal_lines(tree: ast.AST) -> set[int]:
    out: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and len(node.value) > 3:
            out.add(node.lineno)
    return out


def comment_lines(src: str) -> dict[int, str]:
    out = {}
    try:
        for tok in tokenize.generate_tokens(io.StringIO(src).readline):
            if tok.type == tokenize.COMMENT:
                out[tok.start[0]] = tok.string
    except Exception:
        pass
    return out


def main() -> int:
    rows = parse_rows()
    out = []
    for path, citers in rows:
        out.append(f"=== PATH {path}")
        for rel in citers:
            fp = os.path.join(ROOT, rel)
            if not os.path.isfile(fp):
                out.append(f"  CITER {rel}: NOT ON DISK (citer itself is gone)")
                continue
            src = open(fp, encoding="utf-8", errors="replace").read()
            out.append(f"  CITER {rel}  ({len(src.splitlines())} lines)")
            if rel.endswith(".py"):
                try:
                    tree = ast.parse(src)
                except SyntaxError as exc:
                    out.append(f"    SYNTAXERROR {exc}")
                    tree = None
                docs = docstring_nodes(tree) if tree else set()
                keys = dict_key_lines(tree) if tree else set()
                lits = literal_lines(tree) if tree else set()
                comments = comment_lines(src)
                for i, line in enumerate(src.splitlines(), 1):
                    if path in line:
                        tags = []
                        if i in docs:
                            tags.append("DOCSTRING")
                        if i in comments:
                            tags.append("COMMENT")
                        if i in keys:
                            tags.append("DICT_KEY")
                        if i in lits:
                            tags.append("STRING_LIT")
                        out.append(f"    L{i:<5} [{','.join(tags) or 'BARE'}] {line.strip()[:190]}")
            else:
                for i, line in enumerate(src.splitlines(), 1):
                    if path in line:
                        out.append(f"    L{i:<5} [SHELL]     {line.strip()[:190]}")
    open(os.path.join(HERE, "mentions.rows"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"paths={len(rows)} citer-pairs={sum(len(c) for _, c in rows)} lines={len(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())