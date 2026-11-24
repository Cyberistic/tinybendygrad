#!/usr/bin/env python3
"""**THE **COST **OF **THE **PRELUDE's **`String.split`** **IN **THE **DECODE**, **MEASURED **IN **THE
**DAEMON** -- **⇒⇒† AND **AND **THE **PORT **ALREADY **MOVED **THE **WIRE's **SPLIT **TO **A **JS
**EFFECT** (⇒⇒† AND **§125/§126**) **⇒⇒† AND **AND **THE **PAYLOAD's **SPLITS **ARE **STILL **THE
**PRELUDE's**.

**⇒⇒† AND **THE **PRELUDE's **`String.split`** **IS **ONE **RECURSION **PER **CHARACTER** (⇒⇒† AND **AND
**IT **DOES **A **TOKEN **CONCATENATION **PER **CHARACTER**) -- **⇒⇒† AND **AND **THE **PORT's **OWN
**COMMENT **SAYS **THE **INTERPRETER **CHARGES **~18 ns **A **CALL** (⇒⇒† AND **`live.bend:323`**) -- **⇒⇒†
**AND **AND **THE **PAYLOAD **SPLITS **ARE **SHORT** (⇒⇒† AND **THE **`i`/`p`/`q` **PAYLOADS **ARE **A
**FEW **FIELDS**) -- **⇒⇒† AND **AND **SO **THE **QUESTION **IS **HOW **MANY **OF **THEM **THERE **ARE**.
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
globalThis.__YM = (k, t0) => { globalThis.__Y[k] = (globalThis.__Y[k] || 0) + (performance.now() - t0); };
globalThis.__YN = (k) => { globalThis.__Y[k + ".n"] = (globalThis.__Y[k + ".n"] || 0) + 1; };"""


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
  # **THE **PRELUDE's **`String.split`** -- **⇒⇒† AND **AND **IT **IS **A **RECURSION**, **⇒⇒† AND **AND
  # **SO **A **WRAPPER **IS **NOT **AVAILABLE** (⇒⇒† AND **AND **THE **TREE's OWN **RULE**)** -- **⇒⇒† AND
  # **AND **THE **COUNT **IS **AT **THE **RECURSIVE **CALL's **SITE** (⇒⇒† AND **AND **THE **COUNT **IS
  # **THE **CHARACTER **COUNT**)**.
  m = re.search(r"function (\$String_split)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_split")
  fname, params = m.group(1), m.group(2)
  i, end = find_fn(src, fname)
  body = src[i:end]
  # **⇒⇒† AND **THE **RECURSIVE **CALL **INSIDE** (⇒⇒† AND **AND **THE **COUNT **IS **THE **CHARACTERS**)**.
  recs = re.findall(r"\$\$String_split\(([^)]*)\)", body)
  if not recs:
    raise SystemExit("WARN: no recursive call in String_split")
  newbody = body
  for r in set(recs):
    newbody = newbody.replace(r"$" + r, f"globalThis.__YN(\"split\"), ${r}")
  # **⇒⇒† AND **AND **THE **ENTRY's **COUNT** (⇒⇒† AND **AND **THE **ENTRY **IS **THE **CALL **SITE**)**
  newbody = newbody.replace("{", "{\n  globalThis.__YN(\"split\");", 1)
  src = src[:i] + newbody + src[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".ys",
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
  out_path = BUILD / f"serve_ysplit_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"ysplit{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".ys").read_text())
  Y = data.get("Y", {})
  n = 60
  print()
  print(f"THE **PRELUDE's **`String.split`**, IN THE DAEMON ({n} turns):")
  print(f"  the CALLS (the CHARACTERS walked): {Y.get('split.n', 0)/n:.0f} a turn")


if __name__ == "__main__":
  main()
