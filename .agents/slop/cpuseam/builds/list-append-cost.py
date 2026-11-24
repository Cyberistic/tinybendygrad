#!/usr/bin/env python3
"""**THE **COST **FACTOR **OF **EVERY **`List.append`**, **BY **ITS **CALLER** -- **⇒⇒† AND **AND **THE
**COST **OF **AN **APPEND **IS **THE **LENGTH **OF **ITS **ACCUMULATOR**.

**WHY.** `bend2/base.bend:1003`: **`List.append(xs, ys)`** **COPIES **`xs`** -- **⇒⇒† AND **AND **SO
**`List.append(acc, [x])` **IS **O(|acc|)** (⇒⇒† AND **AND **THE **PORT's **OWN **COMMENT **SAYS **SO
**AT **`cstyle.bend:1497`**)**. **⇒⇒† AND **AND **THE **COST **FACTOR **IS **THE **ACCUMULATOR's
**LENGTH**, **⇒⇒† AND **AND **THE **ACCUMULATOR **IS **THE **CALL's **FIRST **ARGUMENT**.

**⇒⇒† AND **AND **THE **CORRECTION** (MEASURED, `list-concat-ceiling.py`): **THE **JS **LANE's
**`List.append`** **COPIES **THE **SPINE **AND **NOT **THE **ELEMENTS** (⇒⇒† AND **THE **COMPILED
**FORM **IS **`{$: "Con", "head": _h_0, "tail": $$List_append(_t_0, _ys_0)}`** -- **⇒⇒† AND **AND **THE
**ELEMENT **IS **SHARED**) -- **⇒⇒† AND **AND **SO **THE **COST **IS **A **CONS **CELL **PER **ELEMENT
**AND **NOT **A **CHARACTER **COPY**, **⇒⇒† AND **AND **AND **THE **CEILING **OF **REMOVING **THE
**COPY **ENTIRELY **IS **0.9853 **ON **THE **MINIMA** (⇒⇒† AND **AGAINST **A **NOISE **FLOOR **OF
**0.9905**)** -- **⇒⇒† AND **AND **SO **THE **LIST **SPINE **IS **NOT **THE **TARGET**.

**⇒⇒† AND **THIS **INSTRUMENT **PATCHES **THE **PRELUDE's **`List.append`** (⇒⇒† AND **ONE **SITE**,
**⇒⇒† AND **AND **SO **THERE **IS **NO **CALL-SITE **PATCHING **AND **NO **NESTED-SITE **PROBLEM**),
**⇒⇒† AND **AND **IT **RECORDS **THE **LENGTH **AND **THE **CALLER** (⇒⇒† AND **VIA **THE **STACK**,
**⇒⇒† AND **AND **THE **TREE's OWN **LESSON **FROM **§138's **ARG_OF **COUNTING**: **THE **COUNT **IS
**THE **MULTIPLIER**)**
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

ACC = """globalThis.__A = globalThis.__A || {};
globalThis.__AP = (k, n) => { const A = globalThis.__A; A[k] = (A[k] || 0) + 1;
  A[k + ".len"] = (A[k + ".len"] || 0) + n; A[k + ".max"] = Math.max(A[k + ".max"] || 0, n); };
globalThis.__ALN = (c) => { let l = 0; while (c && c.$ === "Con") { l += 1; c = c.tail; } return l; };"""


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
  # **THE **PRELUDE's **`List.append`** -- **⇒⇒† AND **ITS **FIRST **ARGUMENT **IS **THE
  # **ACCUMULATOR** (⇒⇒† AND **AND **THE **ARGUMENT **IS **`_xs_0`**)**
  m = re.search(r"function (\$List_append)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $List_append")
  fname, params = m.group(1), m.group(2)
  i, end = find_fn(src, fname)
  body = src[i:end]
  inner = fname + "__orig"
  body = body.replace(f"function {fname}(", f"function {inner}(", 1)
  args = ", ".join(p.strip() for p in params.split(","))
  wrapper = (f"function {fname}({params}) {{\n"
             f"  const __st = new Error().stack;\n"
             f"  const __fr = __st.match(/at (\\$?[A-Za-z0-9_]+)/g) || [];\n"
             f"  const __who = __fr.length > 2 ? __fr[2].slice(3) : (__fr.length ? __fr[__fr.length-1].slice(3) : \"?\");\n"
             f"  globalThis.__AP(__who, globalThis.__ALN({args.split(',')[0].strip()}));\n"
             f"  return {inner}({args});\n"
             f"}}")
  src = src[:i] + body + "\n" + wrapper + src[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".ap",
        JSON.stringify({A: globalThis.__A || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_apcost_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"apcost{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".ap").read_text())
  A = data.get("A", {})
  n = 60
  rows = []
  for k, v in A.items():
    if ".len" in k or ".max" in k:
      continue
    cnt = v / n
    ln = A.get(k + ".len", 0) / n
    mx = A.get(k + ".max", 0)
    if cnt <= 0:
      continue
    short = k.replace("$_________tinybendygrad_renderer_cstyle_", "").replace("$", "")
    rows.append((cnt * ln, cnt, ln, mx, short))
  rows.sort(reverse=True)
  print()
  print("THE **`List.append`**, **BY **ITS **CALLER** -- **THE **COST **FACTOR **IS **THE "
        "**ACCUMULATOR's **LENGTH**")
  print("  %10s %8s %8s %6s  %s" % ("calls x len", "calls", "mean len", "max", "THE CALLER"))
  for cost, cnt, ln, mx, short in rows[:16]:
    print("  %10.0f %8.1f %8.1f %6d  %s" % (cost, cnt, ln, mx, short))
  print()
  print(f"  THE TOTAL calls x len: {sum(r[0] for r in rows):.0f} a turn")


if __name__ == "__main__":
  main()
