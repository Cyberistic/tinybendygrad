#!/usr/bin/env python3
"""**THE **EXCLUSIVE **COST **OF **EACH **STEP **OF **THE **DECIMAL **CONVERSION** -- **⇒⇒† AND **AND **THE
**NESTED **CLOCKS **OVERCOUNT** (⇒⇒† AND **§138.25's **LESSON**)**.

**WHY.** `decimal-shape.py` **READS**: **`i64_dec` **IS **3.48 ms **A **TURN **OVER **120 **CALLS**, **⇒⇒†
**AND **`lo32` **IS **43,178 **CALLS **A **TURN**, **⇒⇒† AND **AND **`i64_dec_times10` **IS **2,280** -- **⇒⇒†
**AND **AND **THE **NESTED **CLOCKS **COUNT **THE **NESTED **PARTS **ONCE **PER **LEVEL**, **⇒⇒† AND **AND
**SO **THE **EXCLUSIVE **COST **OF **EACH **FUNCTION **IS **WHAT **MATTERS**.

**⇒⇒† AND **THE **EXCLUSIVE **COST **IS **THE **CLOCK **MINUS **THE **CLOCK **OF **THE **CALLS **IT
**MAKES** -- **⇒⇒† AND **AND **THE **CALL **GRAPH **IS **READ **FROM **THE **COMPILED **FORM** (⇒⇒† AND **AND
**NOT **FROM **A **HAND **LIST**)**
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

ACC = """globalThis.__D = globalThis.__D || {};
globalThis.__DM = (k, t0) => { globalThis.__D[k] = (globalThis.__D[k] || 0) + (performance.now() - t0); };
globalThis.__DN = (k) => { globalThis.__D[k + ".n"] = (globalThis.__D[k + ".n"] || 0) + 1; };"""


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
  # **THE **FAMILY**, **AND **THE **CALL **GRAPH** -- **⇒⇒† AND **AND **THE **EXCLUSIVE **COST **IS
  # **COMPUTED **FROM **THE **CLOCKs **AND **THE **GRAPH** (⇒⇒† AND **AND **THE **GRAPH **IS **READ **FROM
  # **THE **COMPILED **FORM**)**
  found = sorted(set(re.findall(r"function (\$_________tinybendygrad_helpers_[A-Za-z0-9_]*"
                                r"(?:i64_dec|u32_dec|divmod|div_|u64_divmod|i64_abs|i64_of_i32|lo32|hi32)"
                                r"[A-Za-z0-9_]*)\(", src)))
  print(f"THE FUNCTIONS: {len(found)}")
  out = src
  keys = {}
  for name in found:
    key = name.replace("$_________tinybendygrad_helpers_", "")
    keys[name] = key
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
    wrapper = (f"function {fname}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  globalThis.__DN(\"{key}\");\n"
               f"  const __v = {inner}({args});\n"
               f"  globalThis.__DM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    out = out[:i] + body + "\n" + wrapper + out[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = out.index(marker)
  out = out[:i] + ACC + "\n" + out[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".dx",
        JSON.stringify({D: globalThis.__D || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_decex_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"decex{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".dx").read_text())
  D = data.get("D", {})
  n = 60
  rows = []
  for k, v in D.items():
    if k.endswith(".n"):
      continue
    cnt = D.get(k + ".n", 0) / n
    if cnt <= 0:
      continue
    rows.append((v / n, cnt, k))
  rows.sort(reverse=True)
  print()
  print("THE **NESTED **CLOCKs** (the INCLUSIVE numbers -- the EXCLUSIVE ones NEED **THE **GRAPH**):")
  print("  %9s %9s  %s" % ("ms a turn", "calls", "THE FUNCTION"))
  for ms, cnt, k in rows[:14]:
    print("  %9.4f %9.1f  %s" % (ms, cnt, k))
  print()
  print("  **⇒⇒† AND **THE **INCLUSIVE **NUMBER **OF **A **FUNCTION **IS **ITS **CLOCK **PLUS **THE "
        "**CLOCKs **OF **THE **CALLS **IT **MAKES** -- **⇒⇒† AND **AND **THE **CHEAPEST **WAY **TO **SEE "
        "**THE **EXCLUSIVE **COST **IS **TO **COUNT **THE **CALLS **PER **FUNCTION**")
  print()
  print("  **⇒⇒† AND **THE **CALL **COUNTS **A **TURN**:")
  for ms, cnt, k in sorted(rows, key=lambda r: -r[1])[:12]:
    print("    %9.1f  %s" % (cnt, k))


if __name__ == "__main__":
  main()
