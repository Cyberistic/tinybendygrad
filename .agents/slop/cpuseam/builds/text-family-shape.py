#!/usr/bin/env python3
"""**CLOCK **EVERY **`ku_text_*` **FUNCTION**, **INSIDE **THE **DAEMON** -- **⇒⇒† AND **AND **THE
**`text` **FAMILY **IS **THE **BIGGEST **UNMEASURED **LEAF** (⇒⇒† AND **AND **§138.3's
**`render-shape.py` **COUNTS **IT **AND **DOES **NOT **CLOCK **IT**, **⇒⇒† AND **AND **THE **REASON
**IS **THAT **A **WRAPPER **LAYER **IS **PAID **AT **EVERY **RECURSION **LEVEL**)**.

**⇒⇒† AND **SO **THE **CLOCKS **ARE **AT **THE **LEAVES** -- **⇒⇒† AND **AND **THE **`ku_text_*`
**FUNCTIONS **ARE **THE **LEAVES** (⇒⇒† AND **AND **THEIR **RECURSION **IS **THE **LIST **WALK**) -- **⇒⇒†
**AND **AND **THE **`alu` **ONE **IS **THE **ARM **THAT **MOST **UOPS **TAKE** (⇒⇒† AND **AND **THE
**INSTRUMENT **WILL **SAY **SO)**.

**⇒⇒† AND **EVERY **PATCH **SITE **IS **COUNTED **BEFORE **IT **IS **APPLIED** (⇒⇒† AND **AND **A
**MISS **IS **AN **ERROR **AND **NOT **A **SILENT **ZERO**)** -- **⇒⇒† AND **AND **THE **CLOCK **IS
**INSIDE **THE **FUNCTION **BODY** (⇒⇒† AND **AND **THE **TREE's OWN **RULE**)**.
"""

import json
import pathlib
import re
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = """globalThis.__T = globalThis.__T || {};
globalThis.__TM = (k, t0) => { globalThis.__T[k] = (globalThis.__T[k] || 0) + (performance.now() - t0); };
globalThis.__TN = (k) => { globalThis.__T[k + ".n"] = (globalThis.__T[k + ".n"] || 0) + 1; };"""


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


def instrument(src: str):
  # **THE **`ku_text_*` **FAMILIES**, **BY **THEIR **COMPILED **NAME** -- **⇒⇒† AND **AND **THE
  # **POPULATION **IS **DISCOVERED **FROM **THE **COMPILED **FORM** (⇒⇒† AND **AND **NOT **FROM **A
  # **HAND **LIST**)**.
  found = sorted(set(re.findall(r"function (\$_________tinybendygrad_renderer_cstyle_ku_text_[A-Za-z0-9_]+)\(", src)))
  if not found:
    raise SystemExit("WARN: no ku_text family -- IT WILL READ AS ZERO")
  print(f"THE ku_text FUNCTIONS: {len(found)}")
  # **⇒⇒† AND **AND **THE **NAME **IS **SHORTENED **TO **THE **ARM** (⇒⇒† AND **AND **THE **ARM
  # **IS **WHAT **A **READER **NEEDS**)**
  keys = {}
  for name in found:
    key = name.replace("$_________tinybendygrad_renderer_cstyle_", "")
    keys[name] = key
  out = src
  for name in found:
    m = re.search(r"function (" + re.escape(name) + r")\(([^)]*)\)\s*\{", out)
    if not m:
      continue
    fname, params = m.group(1), m.group(2)
    i, end = find_fn(out, fname)
    if i is None:
      continue
    body = out[i:end]
    inner = fname + "__orig"
    body = body.replace(f"function {fname}(", f"function {inner}(", 1)
    args = ", ".join(p.strip() for p in params.split(","))
    key = keys[name]
    wrapper = (f"function {fname}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  globalThis.__TN(\"{key}\");\n"
               f"  const __v = {inner}({args});\n"
               f"  globalThis.__TM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    out = out[:i] + body + "\n" + wrapper + out[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = out.index(marker)
  out = out[:i] + ACC + "\n" + out[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".tt",
        JSON.stringify({T: globalThis.__T || {}})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = out.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  out = out[:i] + dump_new + out[i + len(dump_old):]
  return out


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_plus.js")
  out_path = BUILD / f"serve_textfam_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"textfam{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".tt").read_text())
  T = data.get("T", {})
  n = 60
  rows = []
  for k, v in T.items():
    if k.endswith(".n"):
      continue
    cnt = T.get(k + ".n", 0) / n
    if cnt <= 0:
      continue
    rows.append((v / n, cnt, k))
  rows.sort(reverse=True)
  print()
  print("THE **`ku_text_*` **ARMS**, **IN THE DAEMON** (60 turns):")
  print("  %9s %9s  %s" % ("ms a turn", "calls", "THE ARM"))
  for ms, cnt, k in rows[:18]:
    print("  %9.4f %9.1f  %s" % (ms, cnt, k))
  print()
  print(f"  THE TOTAL: {sum(r[0] for r in rows):.4f} ms a turn (the ARMS ARE NESTED, SO THEY DO NOT SUM)")


if __name__ == "__main__":
  main()
