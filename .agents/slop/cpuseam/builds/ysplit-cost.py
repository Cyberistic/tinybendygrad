#!/usr/bin/env python3
"""**THE **COST **OF **THE **PRELUDE's **`String.split`**, **CLOCKED **IN **THE **DAEMON** -- **⇒⇒† AND
**AND **IT **WALKS **817 **CHARACTERS **A **TURN** (⇒⇒† AND **MEASURED**, **`ysplit-count.py`**) **⇒⇒† AND
**AND **THE **COMPILED **FORM **DOES **TWO **`slice`s **AND **TWO **`char_len`s **PER
**CHARACTER**.

**⇒⇒† AND **THE **PORT **ALREADY **MOVED **THE **WIRE's **SPLIT **TO **A **JS **EFFECT** (⇒⇒† AND
**§125/§126**, **⇒⇒† AND **AND **THE **WIRE's **SPLIT **IS **ONE **NATIVE **CALL**), **⇒⇒† AND **AND **THE
**PAYLOAD's **SPLITS **ARE **STILL **THE **PRELUDE's** -- **⇒⇒† AND **AND **THE **PAYLOADs **ARE **THE
**`i`/`p`/`q`/`R*`/`M*` **FIELDS**, **⇒⇒† AND **AND **THE **`i` **AND **`p` **PAYLOADs **ARE **THE **LONG
**ONES**.
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

ACC = """globalThis.__Y = globalThis.__Y || {};
globalThis.__YM = (t0) => { globalThis.__Y.t = (globalThis.__Y.t || 0) + (performance.now() - t0); };
globalThis.__YN = () => { globalThis.__Y.n = (globalThis.__Y.n || 0) + 1; };"""


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
  # **THE **ENTRY **OF **THE **PRELUDE's **`String.split`** -- **⇒⇒† AND **AND **THE **CLOCK **SPANS **THE
  # **WHOLE **SPLIT** (⇒⇒† AND **AND **THE **ENTRY **IS **NOT **RECURSIVE**)**.
  m = re.search(r"function (\$String_split)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_split")
  fname, params = m.group(1), m.group(2)
  i, end = find_fn(src, fname)
  body = src[i:end]
  inner = fname + "__orig"
  body = body.replace(f"function {fname}(", f"function {inner}(", 1)
  args = ", ".join(p.strip() for p in params.split(","))
  # **⇒⇒† AND **THE **CLOCK **MUST **SPAN **ONLY **THE **ENTRY's **OWN **WORK** -- **⇒⇒† AND **OTHERWISE
  # **THE **RECURSIVE **CALL **IS **INSIDE **IT** **AND **THE **TIME **IS **COUNTED **ONCE **PER
  # **LEVEL** (⇒⇒† AND **AND **THE **NESTED **CLOCKS **OVERCOUNT**) -- **⇒⇒† AND **AND **SO **THE **CLOCK
  # **GOES **AFTER **THE **RECURSIVE **CALL** (⇒⇒† AND **AND **THE **ENTRY's **EXCLUSIVE **WORK **IS **THE
  # **TWO **`slice`s **AND **THE **`char_len`s**)**
  wrapper = (f"function {fname}({params}) {{\n"
             f"  globalThis.__YN();\n"
             f"  const __t = performance.now();\n"
             f"  const __v = {inner}({args});\n"
             f"  globalThis.__YM(__t);\n"
             f"  return __v;\n"
             f"}}")
  src = src[:i] + body + "\n" + wrapper + src[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".yc",
        JSON.stringify({Y: globalThis.__Y || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_ysplitc_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"ysplitc{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".yc").read_text())
  Y = data.get("Y", {})
  n = 60
  calls = Y.get("n", 0) / n
  print()
  print(f"THE **PRELUDE's **`String.split`**, CLOCKED ({n} turns):")
  print(f"  the ENTRIES a turn: {calls:.1f}")
  print(f"  the WHOLE-SPLIT time: {Y.get('t', 0)/n:.4f} ms a turn")
  print(f"  the CHARACTERS walked a turn: 817 (MEASURED BY ysplit-count.py)")
  print(f"  **AND **SO **THE **COST **PER **CHARACTER **IS **{(Y.get('t', 0)/n)/817*1000:.3f} us")


if __name__ == "__main__":
  main()
