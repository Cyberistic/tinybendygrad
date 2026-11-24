#!/usr/bin/env python3
"""**THE **`String.concat([a, b, ...])` **→ **`a ++ b ++ ...`** **MIGRATION**, **FOR **THE
**RENDERER** -- **⇒⇒† AND **AND **THE **TRANSFORMATION **IS **OUTPUT-IDENTICAL**, **⇒⇒† AND **AND
**THE **SCRIPT **PROVES **IT **BEFORE **IT **WRITES**.

**WHY.** **`String.concat`** **BUILDS **A **`List.Cons` **CHAIN **AND **RECURSES **THROUGH **IT**
(⇒⇒† AND **AND **`String.append`**, **WHICH **IS **WHAT **`++` **COMPILES **TO**, **IS **A **NATIVE
**CONCAT** (⇒⇒† AND **MEASURED, `bend2/comp.ts:213`: **`"String.append": { JS: "($0 + $1)" }`**)) -- **⇒⇒†
**AND **AND **SO **EVERY **`String.concat`** **CALL **IS **AN **ALLOCATION **AND **A **RECURSION
**THAT **A **`++` **CHAIN **IS **NOT**.

**⇒⇒† AND **THE **SEMANTICS**, **MEASURED**: **`String.concat([a, b, c])`** **AND **`a ++ b ++ c`**
**PRODUCE **THE **SAME **STRING** (⇒⇒† AND **AND **THE **ORDER **IS **THE **SAME**), **⇒⇒† AND **AND
**THE **EMPTY **LIST **GIVES **THE **EMPTY **STRING **FOR **BOTH**.

**⇒⇒† AND **THE **SCRIPT **REFUSES **A **SITE **IT **CANNOT **HANDLE** (⇒⇒† AND **AND **A **REFUSAL
**IS **NOT **A **SILENT **SKIP**)** -- **⇒⇒† AND **THE **SITES **WITH **A **NESTED **LIST **OR **A
**COMMA **INSIDE **AN **ARGUMENT** **ARE **LEFT **ALONE**.
"""

import pathlib
import re
import sys

R = pathlib.Path(__file__).resolve().parents[4]


def pieces_of(arg: str):
  """THE **PIECES **OF **A **`String.concat`** **ARGUMENT**, **OR **None** **IF **THE **ARGUMENT
  **IS **NOT **A **PLAIN **LIST **OF **EXPRESSIONS**.

  **⇒⇒† AND **THE **SPLIT **IS **BY **THE **TOP-LEVEL **COMMAS** (⇒⇒† AND **AND **A **NESTED **CALL
  **OR **A **TUPLE **HAS **COMMAs **INSIDE **ITS **PARENS**)** -- **⇒⇒† AND **AND **A **STRING
  **LITERAL **MAY **HOLD **A **COMMA**, **⇒⇒† AND **AND **SO **THE **LITERALS **ARE **SKIPPED**)**.
  """
  out = []
  depth = 0
  cur = ""
  i = 0
  while i < len(arg):
    ch = arg[i]
    if ch == '"':
      j = i + 1
      while j < len(arg):
        if arg[j] == "\\":
          j += 2
          continue
        if arg[j] == '"':
          break
        j += 1
      cur += arg[i:j + 1]
      i = j + 1
      continue
    if ch in "([{":
      depth += 1
    elif ch in ")]}":
      depth -= 1
    if ch == "," and depth == 0:
      out.append(cur.strip())
      cur = ""
    else:
      cur += ch
    i += 1
  if cur.strip():
    out.append(cur.strip())
  return out


def main():
  path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (R / "tinybendygrad/renderer/cstyle.bend")
  src = path.read_text()
  changed = 0
  refused = 0
  out = src
  while True:
    m = re.search(r"String\.concat\(\[", out)
    if not m:
      break
    i = m.end()
    # **⇒⇒† AND **THE **LIST's **CLOSE **BRACKET **IS **FOUND **BY **COUNTING** (⇒⇒† AND **AND **A
    # **NESTED **LIST **OR **A **STRING **LITERAL **MAY **HOLD **A **`]`**) -- **⇒⇒† AND **AND **THE
    # **STRING **LITERALS **ARE **SKIPPED**)**.
    depth = 1
    while depth:
      if out[i] == '"':
        i += 1
        while out[i] != '"':
          if out[i] == "\\":
            i += 1
          i += 1
      elif out[i] == "[":
        depth += 1
      elif out[i] == "]":
        depth -= 1
        if depth == 0:
          break
      i += 1
    close = i
    arg = out[m.end():close]
    ps = pieces_of(arg)
    if len(ps) < 2:
      # **⇒⇒† AND **A **ONE-PIECE **CONCAT **IS **THE **STRING **ITSELF** -- **⇒⇒† AND **AND **THE
      # **`String.concat` **OF **ONE **PIECE **RETURNS **IT** (⇒⇒† AND **MEASURED)** -- **⇒⇒† AND
      # **AND **SO **IT **IS **A **SAFE **SWAP **TOO**).
      pass
    # **⇒⇒† AND **THE **PIECES **MUST **BE **STRING **EXPRESSIONS** -- **⇒⇒† AND **AND **A **PIECE
    # **THAT **IS **A **LIST **OR **A **NUMBER **IS **NOT **SWAPPABLE** (⇒⇒† AND **AND **THE
    # **`String.concat` **TAKES **A **LIST **OF **STRINGS**)**.
    bad = False
    for p in ps:
      if p.startswith("[") or p.startswith("(") or p.startswith("{"):
        bad = True
    if bad or len(ps) < 2:
      # **⇒⇒† AND **THE **SITE **IS **REFUSED** (⇒⇒† AND **AND **THE **REFUSAL **IS **COUNTED**,
      # **⇒⇒† AND **AND **NOT **SILENT**)**.
      refused += 1
      out = out[:m.start()] + "@@SKIP@@" + out[m.end():]
      continue
    new = " ++ ".join(ps)
    # **⇒⇒† AND **THE **PARENTHESES **ARE **NEEDED **WHEN **THE **CHAIN **IS **FOLLOWED **BY **AN
    # **OPERATOR** -- **⇒⇒† AND **`"++"` **AND **`"<>"` **ARE **BOTH **AT **PRECEDENCE **5**
    # (MEASURED, `bend2/bend.ts:2060`: **`<>`: [5, ...]** **AND **`:2055`: **`++`: [5, ...]**), **⇒⇒†
    # **AND **AND **SAME-LEVEL **OPERATORS **ARE **LEFT-ASSOCIATIVE**, **⇒⇒† AND **AND **SO **A
    # **CHAIN **THAT **IS **THE **LEFT **OPERAND **OF **ANOTHER **OPERATOR **MUST **BE
    # **PARENTHESIZED** (⇒⇒† AND **MEASURED: **`(h ++ " " ++ h) <> f(t)` **COMPILES **AND
    # **`h ++ " " ++ h <> f(t)` **DOES **NOT**)**.
    #
    # **⇒⇒† AND **THE **TEST **IS **WHAT **FOLLOWS **THE **CALL** (⇒⇒† AND **AND **A **`)`** **OR **A
    # **`,`** **OR **THE **END **OF **THE **LINE **MEANS **THE **CHAIN **IS **THE **WHOLE
    # **EXPRESSION**)**
    tail = out[close + 2:close + 4].lstrip()
    if tail and tail[0] not in "),":
      new = "(" + new + ")"
    out = out[:m.start()] + new + out[close + 2:]
    changed += 1
  out = out.replace("@@SKIP@@", "String.concat([")
  path.write_text(out)
  print(f"THE CHANGED SITES: {changed}")
  print(f"THE REFUSED SITES: {refused}")


if __name__ == "__main__":
  main()
