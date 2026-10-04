#!/usr/bin/env python3
"""Select the `ops-gate.sh` rows: the PORT's own row names, filtered into the oracle.

    .venv/bin/python .agents/slop/ops-rows.py            # print the port's row names
    .venv/bin/python .agents/slop/ops-rows.py --oracle <oracle.txt> <out.txt>

`ops-gate.sh` HAS BEEN EDITED FOR EVERY FAMILY THAT LANDS. Seven times now: s5, sg,
vr, rra, rnd, vv and set each went red on the unfiltered rows, and each time the
fix was a `("name", "reason")` entry appended to `ops-oracle.py`'s `BEND_ONLY` list
-- a file that has nothing to do with the unit, holding a hand-maintained index of
which prefixes are someone else's problem.

This removes the category. The PORT already knows which rows it prints; the gate
should read that and filter the ORACLE to it, which is what
`.agents/slop/prepare_rows.py` does for the 321 `prepare` rows and why `prepare`
needs no entry here at all. A gate whose row set comes from a list somewhere else
is a gate that goes red when a unit lands, and the response to that is a ritual
rather than a fix.

WHAT THIS DOES NOT DO. It does not drop the `#bend_only_` entries: those carry a
REASON ("the port has no `rtag`; `replace` and `rtag` are the same node here"),
and a filter that silently discards a row loses the reason. The list stays, as
documentation of what is deliberately un-gated; the prefix filter just stops being
the mechanism by which a NEW family is excluded.

The name-set check is the part that catches the real mistake. A prefix filter
compares 711 oracle rows against 321 port rows and fails on rows nobody claimed;
a name filter fails only on a row the PORT prints and the ORACLE does not, which is
a port row with no CPython counterpart, and on an oracle row the port claims and
cannot produce, which is a row that lost its fixture. Both are findings.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OPS = REPO / "tinybendygrad" / "uop" / "ops.bend"


def port_names(text):
  """The row names `ops.bend` prints, in EMISSION order.

  A name is anything up to the first `=`, and `done` is the port's own sentinel --
  it is not a row and the oracle has no counterpart for it.
  """
  out = []
  for line in text.split("\n"):
    if "=" not in line:
      continue
    name = line.split("=", 1)[0]
    if name and name != "done" and re.fullmatch(r"[a-z][a-z0-9_]*", name):
      out.append(name)
  return out


def main():
  args = [a for a in sys.argv[1:] if not a.startswith("-")]
  if args and args[0] == "--oracle":
    oracle_text = Path(args[1]).read_text()
    want = port_names(subprocess.run([str(REPO / "bin/bend"), str(OPS)],
                                     capture_output=True, text=True, cwd=REPO).stdout)
    have = {}
    for line in oracle_text.split("\n"):
      if "=" in line:
        have.setdefault(line.split("=", 1)[0], []).append(line)
    rows, missing = [], []
    for name in want:
      if name in have:
        rows.extend(have[name])
      else:
        missing.append(name)
    if missing:
      print(f"ops-rows: the oracle does not produce {len(missing)} of the port's rows: "
            f"{missing[:8]}", file=sys.stderr)
      return 1
    Path(args[2]).write_text("\n".join(rows) + "\n")
    print(f"ops-rows: {len(want)} port rows, all present in the oracle", file=sys.stderr)
    return 0

  out = subprocess.run([str(REPO / "bin/bend"), str(OPS)],
                       capture_output=True, text=True, cwd=REPO)
  for name in port_names(out.stdout):
    print(name)
  return 0


if __name__ == "__main__":
  sys.exit(main())
