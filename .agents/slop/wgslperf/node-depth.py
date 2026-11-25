#!/usr/bin/env python3
"""**THE **NODE's **DEPTH **MOVES **INTO **THE **NODE**, **AND **THE **ARENA's **SHAPE **LIST **GOES
**AWAY.** **THE **EDIT **IS **MECHANICAL**, **SO **IT **IS **A **SCRIPT **AND **NOT **A **HAND.**

**WHY.** THE ARENA's **`shp` **LIST **IS **A **PARALLEL **ARRAY** (⇒⇒† AND **AND **A **PARALLEL
**ARRAY **IS **A **SECOND **SOURCE **OF **TRUTH**), **⇒⇒† AND **AND **THE **INTERNING **WALKS **IT
**IN **PARALLEL **WITH **THE **NODES**, **⇒⇒† AND **AND **SO **THE **TWO **MUST **BE **THE **SAME
**LENGTH** (⇒⇒† AND **AND **THE **PORT's **OWN **FIXTURES **ARE **NOT**: **`Arena{[...15
NODES...], [0]}`** **IS **A **SHAPE **LIST **OF **ONE**). **AND **THE **DEPTH **IS **ZERO **FOR
**EVERY **NODE**: **MEASURED **17,554 **NODES, **ALL **ZERO**
(**`.agents/slop/wgslperf/count-intern.py` **COUNTS **THE **COMPILED **FORM**).

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/node-depth.py <TREE>` -- **THE **TREE **IS
**A **DIRECTORY **WITH **A **`tinybendygrad/`** **IN **IT** (⇒⇒† AND **AND **THE **SCRATCH **COPY
**IS **WHERE **A **CHANGE **IS **TESTED**)**.
"""

import pathlib
import re
import sys

# **⇒⇒† AND **THE **PATTERNS: **THE **DEPTH **IS **BOUND **WHERE **IT **IS **WANTED **AND **WILDCARDED
# **WHERE **IT **IS **NOT** (⇒⇒† AND **AND **A **BOUND **NAME **THAT **IS **NOT **USED **IS **A **TYPE
# **ERROR**)**.
PATTERNS = [
  # (the file's suffix, the old, the new)
  ("uop/ops.bend", "case Node{op, src, arg, tag}: op", "case Node{op, src, arg, tag, _}: op"),
  ("uop/ops.bend", "case Node{op, src, arg, tag}: src", "case Node{op, src, arg, tag, _}: src"),
  ("uop/ops.bend", "case Node{op, src, arg, tag}: arg", "case Node{op, src, arg, tag, _}: arg"),
  ("uop/ops.bend", "case Node{op, src, arg, tag}: tag", "case Node{op, src, arg, tag, _}: tag"),
  ("uop/ops.bend", "case Node{op, src, arg, tag}: Arena.src_without_body.op(op, src)",
   "case Node{op, src, arg, tag, _}: Arena.src_without_body.op(op, src)"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag} Node{o2, s2, a2, t2}:",
   "    case Node{op, src, arg, tag, d} Node{o2, s2, a2, t2, d2}:"),
  ("uop/ops.bend", "            case Node{_, src, arg, tag} Node{_, s2, a2, t2}:",
   "            case Node{_, src, arg, tag, d} Node{_, s2, a2, t2, d2}:"),
  ("uop/ops.bend", "        case Node{op, src, arg, tag}:", "        case Node{op, src, arg, tag, _}:"),
  ("nn/state.bend", "case O.Node{op, src, arg, tag}: sd_cval.arg(arg)",
   "case O.Node{op, src, arg, tag, _}: sd_cval.arg(arg)"),
  ("codegen/decomp/dtype.bend", "case O.Node{+op, +src, +arg, +tag}: dd_lab.node(op, arg)",
   "case O.Node{+op, +src, +arg, +tag, _}: dd_lab.node(op, arg)"),
  ("uop/fold.bend", "case O.Node{+op, src, +arg, tag}:", "case O.Node{+op, src, +arg, tag, _}:"),
  # THE TYPE
  ("uop/ops.bend", "  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag}",
   "  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag, d: U32}"),
  # THE TWO MAKERS: THE DEPTH IS THE PARAMETER
  ("uop/ops.bend", "  UOp.make.intern(ar, Node{op, src, arg, tag}, depth)",
   "  UOp.make.intern(ar, Node{op, src, arg, tag, depth}, depth)"),
  ("uop/ops.bend", "  UOp.of.intern(ar, Node{op, src, arg, tag}, depth)",
   "  UOp.of.intern(ar, Node{op, src, arg, tag, depth}, depth)"),
]


def close_brace(text: str, open_at: int) -> int:
  """**THE **INDEX **OF **THE **BRACE **THAT **CLOSES **THE **ONE **AT **`open_at`**."""
  depth = 0
  i = open_at
  while i < len(text):
    c = text[i]
    if c == '"':
      i += 1
      while i < len(text):
        if text[i] == "\\":
          i += 2
          continue
        if text[i] == '"':
          break
        i += 1
    elif c == "{":
      depth += 1
    elif c == "}":
      depth -= 1
      if depth == 0:
        return i
    i += 1
  raise SystemExit("WARN: an unbalanced brace")


def constructions(text: str) -> str:
  """**EVERY **`Node{...}`** **CONSTRUCTION **GETS **THE **DEPTH **ZERO**, **AND **THE **MATCHING
  **BRACE **IS **FOUND **BY **COUNTING** (⇒⇒† AND **AND **THE **ARGUMENTS **HAVE **BRACES **OF
  **THEIR **OWN**)"""
  out = []
  i = 0
  while True:
    m = re.compile(r"(?<![A-Za-z0-9_.])(?<!\bcase )((?:O\.)?)Node\{").search(text, i)
    if not m:
      out.append(text[i:])
      break
    out.append(text[i:m.start()])
    ob = text.index("{", m.start())
    cb = close_brace(text, ob)
    body = text[ob + 1:cb]
    out.append(f"{m.group(1)}Node{{{body}, 0}}")
    i = cb + 1
  return "".join(out)


def main():
  root = pathlib.Path(sys.argv[1]) / "tinybendygrad"
  if not root.exists():
    raise SystemExit(f"WARN: there is no tinybendygrad under {sys.argv[1]}")
  files = sorted(root.rglob("*.bend"))
  for f in files:
    text = f.read_text()
    orig = text
    # THE PATTERNS GO FIRST, AND THEY GO BEHIND A PLACEHOLDER (⇒⇒† AND **AND **A **TWO-SCRUTINEE
    # **`case Node{...} Node{...}`** **HAS **A **SECOND **`Node{`** **THAT **IS **NOT **PRECEDED **BY
    # **`case `**, **⇒⇒† AND **SO **A **PLACEHOLDER **IS **THE **ONLY **WAY **TO **KEEP **THE
    # **CONSTRUCTION **PASS **OFF **THEM**).
    holes = []
    for suffix, old, new in PATTERNS:
      if str(f).endswith(suffix):
        if old not in text:
          raise SystemExit(f"WARN: {f} does not have {old!r}")
        mark = f"\x00HOLE{len(holes)}\x00"
        holes.append((mark, new))
        text = text.replace(old, mark)
    text = constructions(text)
    for mark, new in holes:
      text = text.replace(mark, new)
    if text != orig:
      f.write_text(text)
      print(f"  {f.relative_to(root)}")


if __name__ == "__main__":
  main()
