#!/usr/bin/env python3
"""Comment census by tokenizer, population discovered by walk AND by git ls-tree.

Populations (AGENTS.md doctrine 1 -- none of these is a hand list):
  (a) DIRECTORY WALK: os.walk + suffix, so a file nobody listed is still counted.
  (b) `git ls-tree -r HEAD`: trackedness. NOT `git ls-files` -- that reads the
      INDEX, which on this tree held a 66-file/13,389-line staged deletion.
      `ls-tree -r` lists BLOBS, so a tracked DIRECTORY reads as absent.

Lexers (AGENTS.md: "use a tokenizer or AST and SAY WHICH"):
  .py   -> `tokenize` module. COMMENT tokens are comments; a STRING token that is
           the whole body of a module/def/class is a docstring. These are counted
           SEPARATELY, because a docstring is prose while a comment is a note.
  .bend -> no tokenizer ships. `bend_lex` below is a line lexer that tracks `"` and
           `'` string literals so a `#` inside a string is NOT a comment.
           `tinybendygrad/sz.bend:1547` is the witness: "### Changes\\n```\\n".
           VERIFY its lexer against grep on that file; the delta is the instrument.

Outputs: census.tsv (per file), totals.md (the denominators in prose).
"""

import ast
import io
import os
import subprocess
import sys
import tokenize

ROOTS = ("checks", "gates", "tinybendygrad", ".agents/slop")
SUFFIXES = (".py", ".bend")


def tracked() -> set[str]:
    """BLOBS of the tree at HEAD. `ls-tree -r` = files, so no directory entries."""
    out = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", *ROOTS],
        capture_output=True, text=True, check=True,
    ).stdout
    return {line for line in out.splitlines() if line}


def walk() -> set[str]:
    found = set()
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in filenames:
                if name.endswith(SUFFIXES):
                    found.add(os.path.join(dirpath, name))
    return found


def bend_lex(line: str) -> bool:
    """True if `line` has comment text OUTSIDE string/char literals."""
    i, n, quote = 0, len(line), None
    while i < n:
        ch = line[i]
        if ch == "\\":
            i += 2
            continue
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return True
        i += 1
    return False


def py_rows(src: str):
    """-> (comment_lines, docstring_lines, unparseable_reason or None)

    tokenize counts COMMENT tokens; ast counts docstrings. SPLIT ON PURPOSE.
    ast drops comments, so it cannot be the comment counter, and the obvious
    tokenizer heuristic for docstrings is WRONG -- v1 of this file used it and
    UNDERCOUNTED by 9 503 lines over the .py population, because the rule
    "STRING right after a def/class keyword" clears itself on the very next NAME
    token, which is the function's own name. ast.get_docstring is the ground
    truth: it fires only when the STRING is the sole stmt of a body.
    """
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
        tree = ast.parse(src)
    except (tokenize.TokenError, SyntaxError, IndentationError) as exc:
        return 0, 0, f"{type(exc).__name__}: {exc}"

    comments = sum(1 for tok in toks if tok.type == tokenize.COMMENT)
    docstrings = sum(
        len(ast.get_docstring(node, clean=False).splitlines())
        for node in ast.walk(tree)
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
        and ast.get_docstring(node, clean=False)
    )
    return comments, docstrings, None


TOTALS = """MEASURED {n} files, of {both} walked-and-tracked paths
  (os.walk over {walked} on disk; git ls-tree -r HEAD blobs: {tracked} tracked)
  LOC (non-blank)  {loc}
  comment lines    {com}  ({compct:.1f}% of LOC)
  docstring lines  {doc}  ({docpct:.1f}% of LOC)
  PROSE TOTAL      {prose}  ({pct:.1f}% of LOC)"""


def pct(part: int, whole: int) -> float:
    return 100.0 * part / whole if whole else 0.0


def main() -> int:
    track, disk = tracked(), walk()
    rows, bad = [], []
    for path in sorted(disk & track):
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        loc = sum(1 for line in src.splitlines() if line.strip())
        if path.endswith(".py"):
            comments, docstrings, err = py_rows(src)
        else:
            comments = sum(1 for line in src.splitlines() if bend_lex(line))
            docstrings, err = 0, None
        if err:
            bad.append((path, err))
            continue
        rows.append((path, loc, loc - comments - docstrings, comments, docstrings))

    rows.sort(key=lambda r: -(r[3] + r[4]))
    out = io.StringIO()
    out.write("path\tloc\tcode\tcomment\tdocstring\tprose_pct\n")
    for path, loc, code, comments, docstrings in rows:
        out.write(f"{path}\t{loc}\t{code}\t{comments}\t{docstrings}\t{pct(comments + docstrings, loc):.1f}\n")
    with open(os.path.join(os.path.dirname(__file__), "census.tsv"), "w") as fh:
        fh.write(out.getvalue())

    n_loc = sum(r[1] for r in rows)
    n_com = sum(r[3] for r in rows)
    n_doc = sum(r[4] for r in rows)
    print(TOTALS.format(
        n=len(rows), walked=len(disk), tracked=len(track), both=len(disk & track),
        loc=n_loc, com=n_com, compct=pct(n_com, n_loc), doc=n_doc, docpct=pct(n_doc, n_loc),
        prose=n_com + n_doc, pct=pct(n_com + n_doc, n_loc)))
    for path, err in bad:
        print(f"  UNPARSEABLE, EXCLUDED FROM EVERY DENOMINATOR ABOVE: {path}: {err}")
    print("\nTOP 25 BY PROSE LINES")
    for path, loc, code, comments, docstrings in rows[:25]:
        print(f"  {comments + docstrings:5d}/{loc:<5d} {100.0 * (comments + docstrings) / loc:5.1f}%  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
