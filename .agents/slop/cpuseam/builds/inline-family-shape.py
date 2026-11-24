#!/usr/bin/env python3
"""**CLOCK **THE **`ku_inline*` **FAMILY**, **INSIDE **THE **DAEMON** -- **⇒⇒† AND **AND **IT **IS **THE
**LAST **UNMEASURED **LEAF **OF **THE **`text` **FAMILY** (⇒⇒† AND **AND **§138.3's **`render-shape.py`
**COUNTS **IT **AND **DOES **NOT **CLOCK **IT**)**.

**⇒⇒† AND **THE **`inline` **FAMILY **IS **A **BOOLEAN **CHAIN** (⇒⇒† AND **`ku_inline2a` **IS **A
**`Bool.or`/`Bool.and` **TREE **OVER **THE **OP **AND **THE **ADDRSPACE**), **⇒⇒† AND **AND **IT **RUNS
**ONCE **PER **UOP** (⇒⇒† AND **AND **`_render.emit` **CALLS **IT**) -- **⇒⇒† AND **AND **SO **IT **IS **A
**CANDIDATE**).
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

ACC = """globalThis.__I = globalThis.__I || {};
globalThis.__IM = (k, t0) => { globalThis.__I[k] = (globalThis.__I[k] || 0) + (performance.now() - t0); };
globalThis.__IN = (k) => { globalThis.__I[k + ".n"] = (globalThis.__I[k + ".n"] || 0) + 1; };"""


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
  # **THE **`ku_inline*` **FUNCTIONS** -- **⇒⇒† AND **AND **THE **POPULATION **IS **DISCOVERED
  # **FROM **THE **COMPILED **FORM** (⇒⇒† AND **AND **NOT **FROM **A **HAND **LIST**)**.
  found = sorted(set(re.findall(r"function (\$_________tinybendygrad_renderer_cstyle_ku_inline[A-Za-z0-9_]*)\(",
                                src)))
  if not found:
    raise SystemExit("WARN: no ku_inline family -- IT WILL READ AS ZERO")
  print(f"THE ku_inline FUNCTIONS: {len(found)}")
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
    key = fname.replace("$_________tinybendygrad_renderer_cstyle_", "")
    wrapper = (f"function {fname}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  globalThis.__IN(\"{key}\");\n"
               f"  const __v = {inner}({args});\n"
               f"  globalThis.__IM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    out = out[:i] + body + "\n" + wrapper + out[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = out.index(marker)
  out = out[:i] + ACC + "\n" + out[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".ii",
        JSON.stringify({I: globalThis.__I || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_inline_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"inline{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".ii").read_text())
  I = data.get("I", {})
  n = 60
  rows = []
  for k, v in I.items():
    if k.endswith(".n"):
      continue
    cnt = I.get(k + ".n", 0) / n
    if cnt <= 0:
      continue
    rows.append((v / n, cnt, k))
  rows.sort(reverse=True)
  print()
  print("THE **`ku_inline*` **FAMILY**, **IN THE DAEMON** (60 turns):")
  print("  %9s %9s  %s" % ("ms a turn", "calls", "THE FUNCTION"))
  for ms, cnt, k in rows[:12]:
    print("  %9.4f %9.1f  %s" % (ms, cnt, k))
  print()
  print(f"  THE TOTAL: {sum(r[0] for r in rows):.4f} ms a turn (THE ARMS ARE NESTED, SO THEY DO NOT SUM)")


if __name__ == "__main__":
  main()
