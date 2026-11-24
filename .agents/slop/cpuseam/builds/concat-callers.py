#!/usr/bin/env python3
"""**WHO **CALLS **`String.concat`**, **AND **HOW **MANY **PIECES **EACH **CALL **HAS**.

**WHY.** §138.3's `render-shape.py` CLOCKS THE RENDER's PARTS, AND `render-text-shape.py`
**CLOCKS **THE **PRELDE's **STRING **FUNCTIONS** -- **AND **IT **READS**: **`String.concat` **IS
**0.34 ms **A **TURN **OVER **9,967 **CALLS**, **AND **`String.join` **IS **0.27 ms **OVER **691
**CALLS** (⇒⇒† AND **THE **`joingo` **COUNT **IS **2,693 **PIECES **WALKED**, **⇒⇒† AND **THAT **IS
**THE **AMPLIFICATION **FACTOR**).

**⇒⇒† AND **SO **THE **COST **IS **IN **THE **STRING **WORK**, **AND **THE **NEXT **QUESTION **IS
**WHICH **CALL **SITE** -- **AND **A **CALL **SITE **IS **A **CALLER**, **⇒⇒† AND **AND **THE
**CALLERS **ARE **COUNTED **FROM **THE **COMPILED **FORM** (⇒⇒† AND **THE **COMPILED **FORM **IS
**THE **ONLY **PLACE **THE **CALL **SITES **ARE **WRITTEN**, **⇒⇒† AND **AND **THE **PORT's **SOURCE
**IS **THE **BEND **SOURCE**, **⇒⇒† AND **AND **THE **TWO **DO **NOT **AGREE **ONE **TO **ONE**)**.

**⇒⇒† AND **THE **COUNTS **ARE **COUNTS**, **AND **§138's LESSON **IS **THAT **THE **COUNT **IS
**NOT **THE **COST** -- **BUT **THE **COUNT **MULTIPLIES **THE **COST**, **⇒⇒† AND **SO **THE
**COUNTED **CALLERS **ARE **THE **CANDIDATES**, **⇒⇒† AND **AND **THE **VERDICT **IS **A **CLOCK
**A **ROUND** -- **⇒⇒† AND **A **CANDIDATE **THAT **CANNOT **BE **MOVED **IS **NOT **A
**CANDIDATE**).
"""

import pathlib
import re
import sys
from collections import Counter

R = pathlib.Path(__file__).resolve().parents[4]
BUILD = R / ".agents/slop/cpuseam/builds"

JS = BUILD / (sys.argv[1] if len(sys.argv) > 1 else "serve_base.js")
src = JS.read_text()

# **THE **COMPILED **FUNCTION **NAMES**, AND **THE **CALL **SITES **INSIDE **EACH**.
#
# **AND THE **ENCLOSING **FUNCTION **OF **A **CALL **SITE **IS **FOUND **BY **THE **BRACE
# **STRUCTURE** -- **AND **THE **NAIVE **SCAN **CUTS **A **COMPILED **`if/else` **CHAIN **IN
# **HALF** (MEASURED, §138.3: THE `}` THAT CLOSES **THE **FIRST **BRANCH** **IS **AT **DEPTH **0**
# **AND **THE **`else if` **FOLLOWS **IT**)**. **SO THE **SCAN **COUNTS **THE **BRACES** **AND
# **THE **`else`**.
NAMES = re.findall(r"function (\$[A-Za-z0-9_]+)\(", src)
NAMES = sorted(set(NAMES))

# **THE **CALL **SITES**, AND **THE **ENCLOSING **FUNCTION**.
#
# **AND THE **ENCLOSING **FUNCTION **IS **THE **LAST **FUNCTION **HEADER **BEFORE **THE **SITE**
# **AT **DEPTH **0** -- **SO THE **SCAN **TRACKS **THE **DEPTH** **AND **REMEMBERS **THE **HEADER**
# **AT **DEPTH **0**.


def enclosing_sites(call: str):
  """THE **CALL **SITES **OF **`call`**, **WITH **THE **ENCLOSING **FUNCTION**."""
  out = []
  depth = 0
  header = None
  i = 0
  while i < len(src):
    m = re.match(r"function (\$[A-Za-z0-9_]+)\(", src[i:])
    if m and depth == 0:
      header = m.group(1)
    ch = src[i]
    if ch == '"':
      i += 1
      while i < len(src):
        if src[i] == "\\":
          i += 2
          continue
        if src[i] == '"':
          break
        i += 1
    elif ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        rest = src[i + 1:i + 12].lstrip()
        if rest.startswith("else"):
          i += 1
          continue
        header = None
    elif src.startswith(call, i):
      out.append((header, i))
    i += 1
  return out


for call, label in (("$$String_concat(", "String.concat"), ("$String_join(", "String.join")):
  sites = enclosing_sites(call)
  print(f"THE {label} CALL SITES IN THE COMPILED FORM: {len(sites)}")
  c = Counter(h for h, _ in sites)
  for name, n in c.most_common(14):
    short = name.replace("$_________tinybendygrad_renderer_cstyle_", "") if name else "(none)"
    short = short.replace("$", "")
    print(f"  {n:5d}  {short}")
  print()

# **AND THE **PIECES **PER **CALL** -- **THE **AMPLIFICATION** -- **AND **THAT **IS **READ **FROM
# **THE **BEND **SOURCE** (⇒⇒† AND **THE **COMPILED **FORM **DOES **NOT **CARRY **THE **LIST's
# **LENGTH**)**.
print("THE PIECES PER CALL, IN THE BEND SOURCE (the LITERAL LIST's LENGTH):")
bend = R / "tinybendygrad/renderer/cstyle.bend"
b = bend.read_text()
for m in re.finditer(r"String\.concat\(\[([^\]]*)\]\)", b):
  pieces = [p for p in m.group(1).split(",") if p.strip()]
  print(f"  {len(pieces):3d} pieces")
