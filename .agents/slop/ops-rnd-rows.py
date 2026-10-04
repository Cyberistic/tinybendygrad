#!/usr/bin/env python3
"""Row selector for the `rnd_*` gate: drop the DIVERGENT rows and their CONTINUATIONS.

    .venv/bin/python .agents/slop/ops-rnd-rows.py <oracle.txt> <out.txt> 'a|b'

This is a separate file and not a heredoc inside the gate for a reason the gate's
own first version proved: a `\\n` inside a `<< 'PY'` heredoc is mangled on the way
through two levels of shell quoting, and the failure is a `TypeError: can only
concatenate str (not "list")` that reads like a Python bug and is a quoting bug.
`prepare_rows.py` is the same idea for the same reason, and two gates needing the
same shape is how you notice it.

THE CONTINUATIONS ARE THE POINT. CPython's `str(x)` for a node with a src is

    UOp(Ops.GROUP, arg=(), src=(
      UOp(Ops.CONST, arg=1, src=()),))

-- three lines. A row file is one line per row, so a divergent row cannot merely be
`grep -v`'d out of the diff: its continuation would stay behind, the oracle file
would have 13 lines where the port has 11, and the diff would be a diff of line
COUNTS wearing a diff of values' clothes. An indented line belongs to the row above
it, so the row and its continuation go together.
"""
import re
import sys


def select(text, diverge):
  pat = re.compile("^(" + diverge + ")=")
  rows, skipping, dropped = [], False, []
  for line in text.split("\n"):
    if pat.match(line):
      skipping = True
      dropped.append(line.split("=", 1)[0])
      continue
    if skipping and (line.startswith(" ") or not line.strip()):
      continue
    skipping = False
    if line.startswith("rnd_"):
      rows.append(line)
  return rows, dropped


def main() -> int:
  if len(sys.argv) != 4:
    print(__doc__, file=sys.stderr)
    return 2
  rows, dropped = select(open(sys.argv[1]).read(), sys.argv[3])
  if not dropped:
    print(f"ops-rnd-rows: none of [{sys.argv[3]}] is in the oracle -- the gate's "
          f"DIVERGES list has drifted from the oracle", file=sys.stderr)
    return 1
  with open(sys.argv[2], "w") as f:
    f.write("\n".join(rows) + "\n")
  print(f"ops-rnd-rows: dropped {','.join(dropped)} and their continuations; "
        f"{len(rows)} rows remain", file=sys.stderr)
  return 0


if __name__ == "__main__":
  sys.exit(main())
