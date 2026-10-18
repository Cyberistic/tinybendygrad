#!/usr/bin/env python3
"""census.py -- EVERY `param_src(` CALL SITE IN THE PORT, DECLARED BY A DIRECTORY WALK.

Doctrine 1: a population is a generator's own declaration, or a directory walk, or a
regex over the tree's own write sites. This is (b) plus (c): `tinybendygrad/**/*.bend`
by `rglob`, then every line. NOTHING HERE NAMES A FILE OR A CALLEE.

WHY LINE-LOCAL. The first version lexed whole files with one bracket stack and it was
WRONG: `tinybendygrad/codegen/decomp/dtype-mut.bend:2646` carries the string `"# l2i\n"`
-- a `#` INSIDE a string -- and a file-global pass that gets its string state shifted by
one quote swallows the closing `"])`, leaving the stack open to EOF and REFUSING a file
that parses. MEASURED: with a file-global stack that file refuses UNCLOSED; with a
line-local pass it parses. Bend's literals here are single-line, so a line is the
right unit and a line that will not lex is a REFUSED LINE, COUNTED, never a silent skip.

MEASURED, Bend accepts BOTH quote characters: `tinybendygrad/uop/upat.bend:1426` is
`String.split(p, '}')` and scanning that `}` as a bracket refuses the file.

usage: .venv/bin/python census.py [--rows]
"""
from __future__ import annotations

import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3] / "tinybendygrad"
QUOTES = "\"'"
OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {v: k for k, v in OPEN.items()}
SITE = re.compile(r"\bparam_src\(")
CALL = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*\(")


def lex(line: str) -> tuple[str, str | None]:
  """(code, refusal). `code` is the line with any trailing `#` comment blanked. Quote
  spans are consumed left to right and a `#` outside one starts the comment, so an
  apostrophe inside a COMMENT is never mistaken for a literal -- which is why this is
  line-local and a file-global pass is not. A quote with no partner on the line is a
  refusal, because guessing would move a bracket."""
  out = []
  i, n = 0, len(line)
  while i < n:
    ch = line[i]
    if ch in QUOTES:
      j = i + 1
      while j < n and line[j] != ch:
        j += 2 if line[j] == "\\" else 1
      if j >= n:
        return "".join(out), f"UNTERMINATED {ch!r}"
      out.append(line[i:j + 1])
      i = j + 1
      continue
    if ch == "#":
      out.append(" " * (n - i))
      return "".join(out), None
    out.append(ch)
    i += 1
  return "".join(out), None


def enclosing(code: str, at: int) -> str:
  """the innermost call whose argument list contains offset `at`, by a BACKWARD bracket
  walk over code only: a closer raises the debt, an opener that zeroes it is the owner.
  Brackets inside string spans were blanked by `lex`, so this walk sees code brackets."""
  debt = 0
  for i in range(at - 1, -1, -1):
    ch = code[i]
    if ch in CLOSE:
      debt += 1
    elif ch in OPEN:
      if debt == 0:
        return callee_at(code, i)
      debt -= 1
  return "<toplevel>"


def callee_at(code: str, i: int) -> str:
  j = i - 1
  while j >= 0 and (code[j].isalnum() or code[j] in "._"):
    j -= 1
  return code[j + 1:i]


def main() -> None:
  rows_arg = "--rows" in sys.argv
  files = sorted(ROOT.rglob("*.bend"))
  per_class: collections.Counter = collections.Counter()
  per_file: collections.Counter = collections.Counter()
  total = refused = refused_with_site = 0
  for p in files:
    for ln, line in enumerate(p.read_text().split("\n"), 1):
      code, why = lex(line)
      if why:
        refused += 1
        # A refused line that ALSO carries a site is a hole in the population, and it is
        # reported separately so a reader never has to trust that it is empty.
        if SITE.search(line):
          refused_with_site += 1
          print(f"REFUSED-LINE-WITH-A-SITE\t{p.relative_to(ROOT)}:{ln}\t{why}")
        elif rows_arg:
          print(f"REFUSED-LINE\t{p.relative_to(ROOT)}:{ln}\t{why}")
        continue
      for m in SITE.finditer(code):
        if code[:m.start()].rstrip().endswith("def"):
          continue
        who = enclosing(code, m.start())
        rel = str(p.relative_to(ROOT))
        per_class[who] += 1
        per_file[rel] += 1
        total += 1
        if rows_arg:
          print(f"{rel}:{ln}\t{who}\t{' '.join(line.split())[:76]}")
  print(f"FILES-WALKED\t{len(files)}")
  print(f"REFUSED-LINES\t{refused}")
  print(f"REFUSED-LINES-WITH-A-SITE\t{refused_with_site}")
  print(f"TOTAL-param_src-CALL-SITES\t{total}")
  for k, v in per_class.most_common():
    print(f"CLASS\t{k}\t{v}")
  print("--- per file ---")
  for k, v in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"FILE\t{k}\t{v}")


if __name__ == "__main__":
  main()