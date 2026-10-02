#!/usr/bin/env python3
"""Reorder a .bend file so every `def X.go` PRECEDES `def X`.

Bend 2.0.34 in this repo requires a definition before its first use, and the
`.go` helper pattern (a public entry that matches on a Bool it cannot compute,
plus a helper that takes the Bool) splits each pair. Writing them in the natural
reading order -- public first, helper after -- fails to compile, so this moves
each helper up in front of its wrapper and leaves everything else alone.

    usage: .venv/bin/python .agents/slop/bend_go_first.py FILE...
"""
import re
import sys
from pathlib import Path

DEF = re.compile(r"(?m)^def ([A-Za-z_][A-Za-z_0-9.]*)\(")


def blocks(text):
  """every top-level `def` block as (name, start, end)."""
  starts = [m.start() for m in DEF.finditer(text)]
  out = []
  for i, st in enumerate(starts):
    en = starts[i + 1] if i + 1 < len(starts) else len(text)
    out.append((DEF.match(text, st).group(1), st, en))
  return out


def fix(path):
  text = path.read_text()
  bs = blocks(text)
  # the prologue (imports, comments, laws) rides with the first def
  head = text[:bs[0][1]]
  names = [n for n, _, _ in bs]
  order, moved = [], 0
  for n, _, _ in bs:
    base = n.split(".", 1)[0] if "." in n else n
    if base != n and base in names and base in order:
      # a cascade step out of turn: put it immediately BEFORE its base
      order.insert(order.index(base), n)
      moved += 1
      continue
    order.append(n)
  by_name = {n: text[s:e] for n, s, e in bs}
  # a def with no blank-line separation would glue to its predecessor
  # a cascade `A.a1 .. A.a7` is a CHAIN: a1 calls a2 calls a3 ... so the steps
  # have to be emitted deepest-last-number FIRST. The comments carry the Python
  # arm order; the def order is the compiler's, not the reader's.
  def step(n):
    tail = n.split(".", 1)[1] if "." in n else ""
    return int(tail[1:]) if tail[:1] == "a" and tail[1:].isdigit() else None

  # a cascade `A.a1 .. A.a7` is a CHAIN: a1 calls a2 calls a3 ... so the steps
  # have to be emitted deepest-last-number FIRST. The comments carry the Python
  # arm order; the def order is the compiler's, not the reader's. The group
  # stays WHERE IT WAS -- reordering must not float a step above the constants.
  order2 = []
  stems = {n.split(".", 1)[0] for n in order if "." in n and step(n) is not None}
  for n in order:
    if step(n) is None or n.split(".", 1)[0] not in stems:
      order2.append(n)
      continue
    stem = n.split(".", 1)[0]
    grp = sorted((x for x in order if x.split(".", 1)[0] == stem and step(x) is not None),
                 key=step, reverse=True)
    order2 = [x for x in order2 if x not in grp]
    at = len(order2)
    order2[at:at] = grp
  order = order2
  body = "\n".join(by_name[n].rstrip() for n in order) + "\n"
  path.write_text(head + body)
  return moved, len(bs)


for f in sys.argv[1:]:
  m, n = fix(Path(f))
  print(f"{f}: {n} defs, {m} helpers moved ahead of their wrapper")