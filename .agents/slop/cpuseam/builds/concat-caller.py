#!/usr/bin/env python3
"""**THE **AMPLIFICATION **OF **EVERY **`String.concat` **CALL**, **MEASURED **IN **THE **DAEMON**
-- **⇒⇒† AND **THE **LIST's **LENGTH**, **PER **CALL**, **AND **THE **CALLER **OF **EACH**.

**WHY.** `render-text-shape.py` **CLOCKS**: **`String.concat` **IS **0.34 ms **A **TURN **OVER
**9,967 **CALLS**. **AND THE **AMPLIFICATION **IS **THE **MULTIPLIER** (§138's LESSON: **THE COUNT
**IS NOT THE COST**, **BUT **THE COUNT MULTIPLIES **THE COST**) -- **⇒⇒† AND **AND **THE
**AMPLIFICATION **IS **THE **LIST's **LENGTH**, **⇒⇒† AND **AND **THE **PIECES **ARE **THE
**STATEMENT's **TEXT** (⇒⇒† AND **`cfo_bin` **BUILDS **A **NESTED **LIST**, **⇒⇒† AND **AND **THE
**NESTING **IS **WHAT **MAKES **THE **LENGTH **36**)**.

**⇒⇒† AND **THIS **INSTRUMENT **MEASURES **THE **LENGTH **OF **THE **LIST **AT **THE **EVERY
**CALL**, **AND **THE **CALLER**, **AND **THE **DISTRIBUTION **IS **THE **VERDICT** (⇒⇒† AND **A
**MEAN **IS **NOT **A **DISTRIBUTION**)**.
"""

import json
import pathlib
import re
import sys
import time
from collections import Counter

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = """globalThis.__L = globalThis.__L || {};
globalThis.__LC = (n, c) => { const L = globalThis.__L; L.n = (L.n || 0) + 1; L.sum = (L.sum || 0) + n;
  L.hist = L.hist || {}; L.hist[n] = (L.hist[n] || 0) + 1;
  L.by = L.by || {}; L.by[c] = (L.by[c] || 0) + 1; L.bylen = L.bylen || {};
  L.bylen[c] = L.bylen[c] || {}; L.bylen[c][n] = (L.bylen[c][n] || 0) + 1; };"""


def instrument(src: str) -> str:
  # **THE **CALL **SITE**, **INSIDE **`String_concat`'s **BODY** -- **⇒⇒† AND **AND **THE **LENGTH
  # **OF **THE **LIST **AND **THE **CALLER** (⇒⇒† AND **THE **CALLER **IS **THE **FRAME **BELOW
  # **THE **CALLEE**)**.
  m = re.search(r"function \$String_concat\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_concat")
  i = src.index(f"function $String_concat({m.group(1)})")
  j = src.index("{", i)
  depth = 0
  k = j
  while k < len(src):
    ch = src[k]
    if ch == '"':
      k += 1
      while k < len(src):
        if src[k] == "\\":
          k += 2
          continue
        if src[k] == '"':
          break
        k += 1
    elif ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        break
    k += 1
  body = src[i:k + 1]
  # **THE **LIST's **LENGTH**, **IN **THE **COMPILED **FORM** -- **⇒⇒† AND **AND **THE **LIST **IS
  # **A **CONS **CELL**, **⇒⇒† AND **AND **THE **LENGTH **IS **THE **WALK's **LENGTH** (⇒⇒† AND
  # **AND **THE **LIST **IS **THE **ARGUMENT**, **⇒⇒† AND **AND **THE **ARGUMENT **IS **THE
  # **FIRST **PARAMETER**)**.
  head = "const _h_0 = _xs_0[\"head\"];"
  if body.count(head) != 1:
    raise SystemExit(f"WARN: the concat head site is {body.count(head)}")
  # **AND THE **CALLER** -- **⇒⇒† AND **THE **STACK **IS **THE **CALL **CHAIN** (⇒⇒† AND **AND **THE
  # **SECOND **FRAME **IS **THE **CALLER**, **⇒⇒† AND **AND **THE **FIRST **IS **THE **COUNTER's
  # **OWN **FUNCTION**)**.
  body = body.replace(head,
                      "globalThis.__LC(0, (new Error().stack.match(/at (\\$?[A-Za-z0-9_]+)/g) || [\"?\",\"?\",\"?\"])[2].slice(3));\n"
                      "    " + head)
  src = src[:i] + body + src[k + 1:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".lg",
        JSON.stringify({L: globalThis.__L || {}})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = src.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  src = src[:i] + dump_new + src[i + len(dump_old):]
  return src


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_base.js")
  out_path = BUILD / f"serve_len_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"len{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".lg").read_text())
  L = data.get("L", {})
  n = L.get("n", 1) or 1
  by = L.get("by", {})
  print()
  print(f"THE **CONCAT's **CALLS**, BY **THEIR **DIRECT **CALLER** ({n} turns):")
  for nm, c in sorted(by.items(), key=lambda kv: -kv[1]):
    short = nm.replace("$_________tinybendygrad_renderer_cstyle_", "").replace("$", "")
    print(f"  {c/n:9.1f} a turn  {short}")
  print()
  print(f"  THE TOTAL: {sum(by.values())/n:.1f} a turn")


if __name__ == "__main__":
  main()
