#!/usr/bin/env python3
"""paramarg-shape-gate.py -- DOES THE PORT'S `ParamArg` STILL HAVE THE SHAPE UPSTREAM HAS?

    .venv/bin/python gates/paramarg-shape-gate.py

TWO LANES AND A ROOT CAUSE, AND THE ROOT CAUSE IS THE PART THAT CANNOT BE DIFFED.
`gates/fold_graph_census-gate.py` is RED today on 11 of 26 compared rows and every one
of them is an `n=` or an `nsrc=` that moved by one, because upstream moved a BUFFER's
size out of `ParamArg` and into `src[0]` (72f98ffe0, "move size from ParamArg to src
(#18624)") and this port did not. This gate measures that move from both ends:

  * the RECORD, field list and ORDER, port against upstream -- `port_fields()` /
    `upstream_fields()`. This is the root cause and it needs no `bend` run.
  * the BEHAVIOUR, `gates/paramarg_shape.bend` against
    `gates/paramarg-shape-oracle.py`. This is the symptom, and today every `nsrc` row
    disagrees while every `shape` and every identity row AGREES.

WHY BOTH, AND WHY THE LANE ALONE IS NOT ENOUGH. A diff of the six lanes says "five
`nsrc` rows disagree". That is true and it does not say what to change, and it is not
stable under a re-vendor: the next one that renames a field moves the lanes without
touching the defect. The record comparison names the field, the index and the value
that occupies it, and it is read from the CLASS at run time so a re-vendor is caught
with no edit to this file -- which is the `differ.declared()` shape
(`AGENTS.md` doctrine 1). A hand list of fields would be the failure
`gates/gates-pop.py:95`'s `HOMES` is, so nothing here names one.

THE PORT'S FIELDS COME FROM A DIRECTORY WALK, AND UNIQUENESS IS A PRECONDITION. `os.walk`
over `tinybendygrad/` for a `type ParamArg is Data:` header: zero hits or two hits is
`REFUSED`, because a comparator that silently compared the wrong record would report a
clean tree over nothing -- the `DEAD` of `gatekit.py:55` wearing a comparison.

THE POSITIVE CONTROL IS THE GATE'S MOST IMPORTANT LINE. An instrument that cannot
detect anything reports a clean zero. So `control_ok()` runs the comparator over two
PLANTED lists -- one equal, one with one field moved -- and a control that does not
behave is `REFUSED`, not `PASS`, because the gate measured nothing.

WHAT THIS GATE IS NOT. It does not re-spell the nine fixtures and it does not migrate
the record. `census()` reports how many sites the migration touches, and the number is
in the rows: the change is `ops.bend` plus every `.bend` file that constructs a
`ParamArg` POSITIONALLY, which `bend` checks for exact arity ("a ParamArg pattern with
12 fields", MEASURED by deleting the field and re-running). A partial migration is a
BUILD BREAK, not a partial gate, so the record and its sites move together or not at
all.
"""
from __future__ import annotations

import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT))
from gatekit import DEAD, FAIL, PASS, REFUSED, Gate, VERDICT, gate  # noqa: E402

PORT_ROOT = ROOT / "tinybendygrad"
SKIP_DIRS = frozenset({"artifacts", "__pycache__", ".git", ".venv", "references", "node_modules"})
HEADER = re.compile(r"^type ParamArg is Data:", re.M)


def _split_top(body: str) -> list[str]:
  """top-level commas only. `<` `>` nest too, because every `Maybe<&2, U32>` field
  holds a comma and a naive split reads one field as three."""
  out, cur, stack = [], [], []
  pairs = {"(": ")", "[": "]", "{": "}", "<": ">"}
  for ch in body:
    if ch in pairs:
      stack.append(pairs[ch])
    elif ch in ")]}>" and stack and ch == stack[-1]:
      stack.pop()
    if ch == "," and not stack:
      out.append("".join(cur))
      cur = []
    else:
      cur.append(ch)
  out.append("".join(cur))
  return [f.strip() for f in out if f.strip()]


def port_fields() -> list[str]:
  """THE PORT'S OWN DECLARATION, in declaration order. Raises if it is not unique.

  The body is taken by BRACE BALANCE and not by "a line that starts with `}`",
  because this record ends `val: Maybe<&2, Const>}` -- the closing brace is on the
  LAST FIELD'S LINE. A line-oriented stop therefore runs to the end of the file and
  reports the next three declarations as ParamArg's fields, which is what the first
  draft of this function did: 3 fields, `slot`, `s`, `Tuple{n, b}`.
  """
  hits = []
  for dp, dn, fn in os.walk(PORT_ROOT):
    dn[:] = sorted(d for d in dn if d not in SKIP_DIRS)
    for f in sorted(fn):
      if not f.endswith(".bend") or f.endswith("-mut.bend") or f.startswith("."):
        continue
      s = (pathlib.Path(dp) / f).read_text()
      for m in HEADER.finditer(s):
        # depth starts at 0, NOT 1: the header itself has no brace -- the record's
        # opening `{` is on the NEXT line (`ParamArg{slot: ...`). Seeding 1 made the
        # scan run to EOF looking for a brace that was never coming, and `if depth:
        # continue` then dropped every hit: 0 found, on a file whose header is there.
        i, depth, opened = m.end(), 0, False
        while i < len(s) and not (opened and depth == 0):
          if s[i] == "{":
            depth, opened = depth + 1, True
          elif s[i] == "}":
            depth -= 1
          i += 1
        if not opened:
          continue
        body = re.sub(r"#[^\n]*", "", s[m.end():i - 1])      # a comment's comma is not a field
        # the span opens with the CONSTRUCTOR's own brace (`ParamArg{slot: ...`), which
        # `_split_top` would hold open to the end and read as one field.
        hits.append([b.split(":")[0].strip() for b in _split_top(body[body.index("{") + 1:])])
  if len(hits) != 1:
    raise LookupError(f"expected exactly one `type ParamArg is Data:` in {PORT_ROOT}, found {len(hits)}")
  return hits[0]


def upstream_fields() -> list[str]:
  """THE CLASS'S OWN DECLARATION, at run time. Nothing in this file names a field."""
  import dataclasses
  from tinygrad.uop.ops import ParamArg
  return [f.name for f in dataclasses.fields(ParamArg)]


def divergences(port: list[str], up: list[str]) -> list[tuple[int, str, str]]:
  """index-wise, in ORDER: a field that MOVED and a field that is MISSING are both
  divergences and they are different defects, so both are named."""
  out = []
  for i in range(max(len(port), len(up))):
    a = port[i] if i < len(port) else "-"
    b = up[i] if i < len(up) else "-"
    if a != b:
      out.append((i, a, b))
  return out


def census(arity: int) -> tuple[int, dict[str, int]]:
  """HOW BIG IS THE MIGRATION. A DIRECTORY WALK, not a glob (`AGENTS.md` doctrine 1:
  `glob('*.bend')` returned `[]` on a tree where the files existed and were tracked)."""
  total, per = 0, {}
  for dp, dn, fn in os.walk(PORT_ROOT):
    dn[:] = sorted(d for d in dn if d not in SKIP_DIRS)
    for f in sorted(fn):
      if not f.endswith(".bend") or f.endswith("-mut.bend") or f.startswith("."):
        continue
      p = pathlib.Path(dp) / f
      s, n = p.read_text(), 0
      for m in re.finditer(r"ParamArg\{", s):
        i, depth = m.end(), 1
        while i < len(s) and depth:
          depth += 1 if s[i] == "{" else (-1 if s[i] == "}" else 0)
          i += 1
        if not depth and len(_split_top(s[m.end():i - 1])) == arity:
          n += 1
      if n:
        per[str(p.relative_to(ROOT))] = n
        total += n
  return total, per


def control_ok() -> bool:
  """THE POSITIVE CONTROL. Two planted lists and ONE assertion each, so a comparator
  that cannot tell them apart cannot tell the tree apart either. The second is the
  DELETED FIELD, which is this gate's own subject: dropping one field shifts every
  index after it, and that is the defect made without a tree."""
  same = ["a", "b", "c"]
  return divergences(same, same) == [] and len(divergences(same[:2], same)) == 1


def structural() -> bool:
  port, up = port_fields(), upstream_fields()
  print(f"port fields ({len(port)})={','.join(port)}")
  print(f"upstream fields ({len(up)})={','.join(up)}")
  for i, a, b in divergences(port, up):
    print(f"DIVERGE index={i} port={a} upstream={b}")
  total, per = census(len(port))
  print(f"migration sites at arity {len(port)}={total} files={len(per)}")
  for f in sorted(per, key=lambda k: -per[k]):
    print(f"  sites={per[f]} {f}")
  return port == up


GATE = Gate(
  "paramarg-shape-gate",
  bend="paramarg_shape.bend",
  oracle="paramarg-shape-oracle.py",
  rows=6,
)

if __name__ == "__main__":
  if not control_ok():
    print("paramarg-shape-gate: REFUSED -- the comparator failed its own control")
    sys.exit(REFUSED)
  try:
    equal = structural()
  except LookupError as e:
    print(f"paramarg-shape-gate: REFUSED -- {e}")
    sys.exit(REFUSED)
  code = gate(GATE, "paramarg-shape-gate: 6 rows, 2 lanes -- every shape and every "
                    "identity row agrees; the nsrc rows are where the size lives, and "
                    "upstream moved it into src[0] and this port did not",
              checks=lambda: equal)
  sys.exit(code)