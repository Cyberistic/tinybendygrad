#!/usr/bin/env python3
"""**THE **OP **HISTOGRAM **OF **THE **`ku_text_go` **DISPATCH**, **MEASURED **IN **THE **DAEMON**
-- **⇒⇒† AND **AND **THE **ARM **ORDER **IS **THE **COST** (⇒⇒† AND **AND **THE **ALU **ARM **IS **THE
**WILDCARD**, **⇒⇒† AND **AND **SO **IT **PAYS **ALL **THE **COMPARISONS **BEFORE **IT**)**.

**⇒⇒† AND **THE **HISTOGRAM **DECIDES **THE **REORDER** (⇒⇒† AND **AND **A **REORDER **IS **ONLY
**RIGHT **IF **THE **HOT **OPS **ARE **KNOWN**)**.
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

ACC = """globalThis.__H = globalThis.__H || {};
globalThis.__HN = (t) => { globalThis.__H[t] = (globalThis.__H[t] || 0) + 1; };"""


def find_fn(src: str, name: str):
  i = src.find(f"function {name}(")
  if i < 0:
    return None, None
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
        return i, k + 1
    k += 1
  return i, None


def instrument(src: str) -> str:
  name = "$_________tinybendygrad_renderer_cstyle_ku_text_go"
  i, end = find_fn(src, name)
  body = src[i:end]
  # **⇒⇒† AND **THE **COUNTER **IS **AT **THE **ENTRY** (⇒⇒† AND **AND **THE **OP **IS **THE
  # **FIRST **PARAMETER**)**
  new = body.replace("{", "{\n  globalThis.__HN(_op_0.$);", 1)
  src = src[:i] + new + src[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".hh",
        JSON.stringify({H: globalThis.__H || {}})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = src.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  src = src[:i] + dump_new + src[i + len(dump_old):]
  return src


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_plus.js")
  out_path = BUILD / f"serve_ophist_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"ophist{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".hh").read_text())
  H = data.get("H", {})
  n = 60
  # **⇒⇒† AND **THE **COMPARISON **COUNT **OF **EACH **OP**, **GIVEN **THE **ARM **ORDER** (⇒⇒† AND **AND
  # **THE **OP **PAYS **THE **COMPARISONS **BEFORE **ITS **ARM**)**
  src = base.read_text()
  i = src.index("function $_________tinybendygrad_renderer_cstyle_ku_text_go(")
  body = src[i:i + 4000]
  order = re.findall(r'_op_0\.\$ === "([A-Za-z0-9_]+)"\)', body)
  pos = {t: k + 1 for k, t in enumerate(order)}
  pos["ALU(wildcard)"] = len(order) + 1
  rows = []
  for tag, c in H.items():
    cnt = c / n
    if cnt <= 0:
      continue
    comparisons = pos.get(tag, len(order) + 1)
    rows.append((cnt * comparisons, cnt, comparisons, tag))
  rows.sort(reverse=True)
  print()
  print("THE **OP **HISTOGRAM **OF **THE **`ku_text_go` **DISPATCH** (60 turns):")
  print("  %12s %9s %7s  %s" % ("comparisons", "calls", "arms", "THE OP"))
  for cost, cnt, comp, tag in rows[:16]:
    print("  %12.0f %9.1f %7d  %s" % (cost, cnt, comp, tag))
  print()
  print(f"  THE TOTAL comparisons a turn: {sum(r[0] for r in rows):.0f}")
  print(f"  THE TOTAL calls a turn:       {sum(r[1] for r in rows):.0f}")
  print()
  print("  **⇒⇒† AND **A **REORDER **THAT **PUTS **THE **HOT **OPS **FIRST **CUTS **THE "
        "**COMPARISONS **TO **THE **SUM **OF **THE **NEW **POSITIONS** -- **⇒⇒† AND **AND **THE "
        "**WILDCARD **STAYS **LAST** **⇒⇒† AND **AND **AND **THE **OP **MUST **STAY **IN **THE "
        "**SAME **ARM**, **⇒⇒† AND **AND **SO **THE **REORDER **IS **PURELY **A **REORDERING **OF "
        "**THE **`match` **ARMS**.")


if __name__ == "__main__":
  main()
