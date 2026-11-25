#!/usr/bin/env python3
"""**THE **NODE **CARRIES **THE **OP's **NUMBER**, **AND **THE **OP **COMPARISON **IS **O(1)**.

**WHY.** `Ops.value` **IS **A **SIXTY-ARM **MATCH**, **⇒⇒† AND **SO **A **CALL **COSTS **THE
**POSITION **OF **ITS **ARM** -- **AND **THE **INTERNING **ASKS **FOR **IT **21,325,576 **TIMES **A
**TURN** (⇒⇒† AND **MEASURED **IN **THE **COMPILED **FORM**, **`.agents/slop/wgslperf/
count-intern.py`**) ✓.

**⇒⇒† AND **THE **NUMBER **IS **CARRIED **BY **THE **NODE**, **AND **NOT **BY **THE **OP's
**VARIANT** (⇒⇒† AND **THE **OP **TYPE **HAS **4,833 **PATTERN **SITES **ACROSS **65 **FILES**,
**⇒⇒† AND **AND **THE **NODE **HAS **23**) ✓ **⇒⇒† AND **AND **THE **NUMBER **IS **COMPUTED
**ONCE, **AT **THE **NODE's **CONSTRUCTION** ✓.

**⇒⇒† AND **THE **VALUES **DO **NOT **MOVE**: **EACH **OP **KEEPS **ITS **OWN **NUMBER** (⇒⇒† AND
**AND **THE **NUMBERS **ARE **THE **DECLARATION **ORDER**, **⇒⇒† AND **AND **THE **PORT **DEPENDS
**ON **THAT**) ✓.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/node-op-value.py <TREE>` -- **THE **TREE
**IS **A **DIRECTORY **WITH **A **`tinybendygrad/`** **IN **IT**.
"""

import pathlib
import re
import sys

# **⇒⇒† AND **THE **NODE's **TYPE **AND **ITS **PATTERNS** (⇒⇒† AND **AND **THE **PATTERNS **BIND
# **POSITIONALLY**, **⇒⇒† AND **AND **THE **NEW **FIELD **IS **LAST **SO **THE **OLD **ONES **KEEP
# **THEIR **PLACES**) ✓.
PATTERNS = [
  ("uop/ops.bend", "  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag, d: U32}",
   "  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag, d: U32, ov: U32}"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, d}: d", "    case Node{op, src, arg, tag, d, _}: d"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, _}: op", "    case Node{op, src, arg, tag, _, _}: op"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, _}: src", "    case Node{op, src, arg, tag, _, _}: src"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, _}: arg", "    case Node{op, src, arg, tag, _, _}: arg"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, _}: tag", "    case Node{op, src, arg, tag, _, _}: tag"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, _}: Arena.src_without_body.op(op, src)",
   "    case Node{op, src, arg, tag, _, _}: Arena.src_without_body.op(op, src)"),
  ("uop/ops.bend", "    case Node{op, src, arg, tag, d} Node{o2, s2, a2, t2, d2}:",
   "    case Node{op, src, arg, tag, d, ov} Node{o2, s2, a2, t2, d2, ov2}:"),
  ("uop/ops.bend", "        case Node{_, src, arg, tag, d} Node{_, s2, a2, t2, d2}:",
   "        case Node{_, src, arg, tag, d, ov} Node{_, s2, a2, t2, d2, ov2}:"),
  ("uop/ops.bend", "        case Node{op, src, arg, tag, _}:", "        case Node{op, src, arg, tag, _, _}:"),
  ("nn/state.bend", "case O.Node{op, src, arg, tag, _}: sd_cval.arg(arg)",
   "case O.Node{op, src, arg, tag, _, _}: sd_cval.arg(arg)"),
  ("codegen/decomp/dtype.bend", "case O.Node{+op, +src, +arg, +tag, _}: dd_lab.node(op, arg)",
   "case O.Node{+op, +src, +arg, +tag, _, _}: dd_lab.node(op, arg)"),
  ("uop/fold.bend", "case O.Node{+op, src, +arg, tag, _}:", "case O.Node{+op, src, +arg, tag, _, _}:"),
]


def close_brace(text: str, open_at: int) -> int:
  depth = 0
  i = open_at
  while i < len(text):
    c = text[i]
    if c == '"':
      i += 1
      while i < len(text):
        if text[i] == "\\":
          i += 1
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


def constructions(text: str, prefix: str) -> str:
  """**EVERY **`Node{...}`** **CONSTRUCTION **GETS **THE **OP's **NUMBER**, **AND **THE **NUMBER
  **IS **`Ops.value`** **OF **THE **OP **THE **SITE **ALREADY **WRITES** (⇒⇒† AND **AND **THE
  **FIRST **ARGUMENT **IS **THE **OP**) ✓"""
  out = []
  i = 0
  pat = re.compile(r"(?<![A-Za-z0-9_.])(?<!\bcase )((?:O\.)?)Node\{")
  while True:
    m = pat.search(text, i)
    if not m:
      out.append(text[i:])
      break
    out.append(text[i:m.start()])
    ob = text.index("{", m.start())
    cb = close_brace(text, ob)
    body = text[ob + 1:cb]
    # **THE **OP **IS **THE **FIRST **ARGUMENT** (⇒⇒† AND **AND **IT **ENDS **AT **THE **FIRST
    # **COMMA **AT **THE **TOP **LEVEL **OF **THE **BRACES**) ✓
    depth = 0
    cut = None
    for j, c in enumerate(body):
      if c in "{[(":
        depth += 1
      elif c in "}])":
        depth -= 1
      elif c == "," and depth == 0:
        cut = j
        break
    if cut is None:
      raise SystemExit(f"WARN: the construction {body!r} has one argument")
    op = body[:cut].strip()
    pre = m.group(1)
    out.append(f"{pre}Node{{{body}, {pre}Ops.value({op})}}")
    i = cb + 1
  return "".join(out)


def main():
  root = pathlib.Path(sys.argv[1]) / "tinybendygrad"
  if not root.exists():
    raise SystemExit(f"WARN: there is no tinybendygrad under {sys.argv[1]}")
  for f in sorted(root.rglob("*.bend")):
    text = f.read_text()
    orig = text
    holes = []
    for suffix, old, new in PATTERNS:
      if str(f).endswith(suffix):
        if old not in text:
          raise SystemExit(f"WARN: {f} does not have {old!r}")
        mark = f"\x00HOLE{len(holes)}\x00"
        holes.append((mark, new))
        text = text.replace(old, mark)
    text = constructions(text, "")
    for mark, new in holes:
      text = text.replace(mark, new)
    if text != orig:
      f.write_text(text)
      print(f"  {f.relative_to(root)}")


if __name__ == "__main__":
  main()
