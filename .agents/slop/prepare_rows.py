#!/usr/bin/env python3
"""The row SELECTOR for the prepare gate, shared by the gate and the mutator.

    .venv/bin/python .agents/slop/prepare-rows.py

`prepare-oracle.py` prints 2500+ rows and `prepare.bend` prints 321, and a prefix
filter does NOT separate them: the oracle emits five EXTRA detail rows per pattern
(`dsk_0_dt`, `dsk_0_fn`, `dsk_0_isany`, `dsk_0_nalts`, `dsk_0_name`) that the port
has no answer for, so a prefix filter compares 711 oracle rows against 321 port rows
and fails on rows that were never claimed.

So the filter is the port's own NAME SET, not a prefix. That is stricter than a
prefix in the useful direction: it also catches a port row the oracle cannot produce,
which a prefix filter would silently drop from both sides.

Why this file exists at all rather than a `grep` in the gate: the mutator needs the
same selection, and two copies of a row filter are two filters that drift. Every
other gate in this tree selects by a single prefix (`s5_`, `sg_`, `vr_`, `rra_`,
`vrn_`) and gets away with it because each of those units is the file's only row
family. `prepare.bend` has SEVEN (`fma_`, `mop_`, `inl_`, `dsk_`, `ear_`, `mcl_`,
`wm_`), which is the point where a prefix stops working and a name set starts.
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
PORT = REPO / "tinybendygrad" / "schedule" / "prepare.bend"

# The families this port prints. `done` is the port's own sentinel and is excluded.
PREFIXES = ("fma_", "mop_", "inl_", "dsk_", "ear_", "mcl_", "wm_")


def port_rows(text: str):
  """[(name, line)] for the port's claimed rows, in emission order."""
  out = []
  for line in text.split("\n"):
    if "=" not in line:
      continue
    name = line.split("=", 1)[0]
    if name == "done" or not name.startswith(PREFIXES):
      continue
    out.append((name, line))
  return out


def select(oracle_text: str, wanted):
  """The oracle's rows for exactly the port's names, in the PORT's order.

  A name the oracle does not produce is reported rather than dropped: a gate that
  cannot say which row it lost is a gate that silently shrinks.
  """
  have = {}
  for line in oracle_text.split("\n"):
    if "=" in line:
      have.setdefault(line.split("=", 1)[0], []).append(line)
  got, missing = [], []
  for name, line in wanted:
    if name not in have:
      missing.append(name)
      continue
    got.append((name, have[name]))
  return got, missing


def main() -> int:
  src = sys.stdin.read() if not sys.stdin.isatty() else PORT.read_text()
  rows = port_rows(src)
  print(f"# {len(rows)} port rows in {len(PREFIXES)} families", file=sys.stderr)
  for _, line in rows:
    print(line)
  return 0


if __name__ == "__main__":
  sys.exit(main())
