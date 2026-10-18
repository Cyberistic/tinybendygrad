#!/usr/bin/env python3
"""nilsrc.py -- EVERY BUFFER/ALLOC/PARAM NODE BUILT WITH AN EMPTY `src`, DISCOVERED.

Same population mechanism as `census.py` (a `rglob` over `tinybendygrad/**/*.bend` plus
the same line lexer), a DIFFERENT question: not "who calls the throwaway-arena helper"
but "who builds a node that OWNS A SIZE and gives it NO src at all".

WHY IT IS A SEPARATE NUMBER AND NOT PART OF THE SELF-LOOP POPULATION. A self-loop is
`src=[i]` where `i` is the node itself: `Arena.src` answers it, and the answer is wrong.
An EMPTY src is `src=[]`: `Arena.src(ar, i, 0)` answers `Maybe.default(..., 0)`, so
`ParamArg.size(ar, i)` -- which reads `src[0]` -- answers `None` and the node simply has
no size. Two different defects that both print `size=N`, and the acceptance rows cannot
tell them apart, so the census has to.

The KIND is NOT A HAND LIST OF NODE NAMES: a node's kind is whatever the SECOND argument
of the constructor is, and a node OWNS A SIZE only if its arg is an `AParam{...}` --
which is the port's own record for a param-shaped node (`ops.bend`'s `ParamArg`). So the
rule is stated structurally and a new param-shaped kind is picked up without editing it.

usage: .venv/bin/python nilsrc.py [--rows]
"""
from __future__ import annotations

import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import census  # noqa: E402
import apply_a as A  # noqa: E402  -- the bracket walker, not copied

ROOT = census.ROOT
CALLS = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*\.UOp\.new\.?\w*\(")


def main() -> None:
  rows_arg = "--rows" in sys.argv
  per_kind: collections.Counter = collections.Counter()
  per_file: collections.Counter = collections.Counter()
  total = 0
  refused = 0
  for p in sorted(ROOT.rglob("*.bend")):
    lines = p.read_text().split("\n")
    for first, last, code, why in A.statements(lines):
      if why:
        refused += len(why)
        continue
      for m in CALLS.finditer(code):
        try:
          end, args = A.span_of(code, m.end() - 1)
        except ValueError:
          continue
        if len(args) != 5 or "AParam" not in args[3]:
          continue
        if A.norm(args[2]) != "Nil{}":
          continue
        kind = A.norm(args[1])
        per_kind[kind] += 1
        per_file[str(p.relative_to(ROOT))] += 1
        total += 1
        if rows_arg:
          ln = code.count("\n", 0, m.start()) + first
          print(f"{p.relative_to(ROOT)}:{ln}\t{kind}\t{' '.join(code.split())[:76]}")
  print(f"FILES-WALKED\t{len(list(ROOT.rglob('*.bend')))}")
  print(f"REFUSED-STATEMENTS\t{refused}")
  print(f"TOTAL-NIL-SRC-PARAM-NODES\t{total}")
  for k, v in per_kind.most_common():
    print(f"KIND\t{k}\t{v}")
  print("--- per file ---")
  for k, v in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"FILE\t{k}\t{v}")


if __name__ == "__main__":
  main()