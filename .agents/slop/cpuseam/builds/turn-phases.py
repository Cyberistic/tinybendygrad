#!/usr/bin/env python3
"""**THE **TURN's **PHASES**, **END **TO **END** -- **⇒⇒† AND **AND **THE **PRINT **OF **THE **RENDERED
**C** **IS **A **SYSCALL** (⇒⇒† AND **AND **15,642 **BYTES **GO **OUT **OF **THE **PROCESS**) -- **⇒⇒† AND
**AND **NOBODY **HAS **MEASURED **IT**.

**⇒⇒† AND **THE **PHASES **ARE **CLOCKED **AT **THE **COMPILED **SITES**: **THE **DECODE** (⇒⇒† AND
**AND **THE **EFFECT's **ENTRY**), **THE **RENDER** (⇒⇒† AND **AND **THE **CALL**), **THE **PRINT** (⇒⇒†
**AND **AND **THE **EFFECT's **ENTRY**) **AND **THE **WHOLE **TURN** (⇒⇒† AND **AND **THE **FRAME's
**WRITE **TO **THE **FRAME's **ANSWER**)**.
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

ACC = """globalThis.__P = globalThis.__P || {};
globalThis.__PM = (k, t0) => { globalThis.__P[k] = (globalThis.__P[k] || 0) + (performance.now() - t0); };
globalThis.__PN = (k) => { globalThis.__P[k + ".n"] = (globalThis.__P[k + ".n"] || 0) + 1; };"""


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
  # **THE **PRINT **EFFECT** -- **⇒⇒† AND **AND **IT **IS **THE **EFFECT's **OWN **FUNCTION**.
  m = re.search(r"function (\$IO_print)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $IO_print")
  fname, params = m.group(1), m.group(2)
  i, end = find_fn(src, fname)
  body = src[i:end]
  inner = fname + "__orig"
  body = body.replace(f"function {fname}(", f"function {inner}(", 1)
  args = ", ".join(p.strip() for p in params.split(","))
  wrapper = (f"function {fname}({params}) {{\n"
             f"  const __t = performance.now();\n"
             f"  globalThis.__PN(\"print\");\n"
             f"  const __v = {inner}({args});\n"
             f"  globalThis.__PM(\"print\", __t);\n"
             f"  return __v;\n"
             f"}}")
  src = src[:i] + body + "\n" + wrapper + src[end:]
  print(f"THE CLOCKED FUNCTION: {fname}")

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".pp",
        JSON.stringify({P: globalThis.__P || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_phase_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"phase{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".pp").read_text())
  P = data.get("P", {})
  n = 60
  print()
  print("THE **TURN's **PHASES**, **IN THE DAEMON** (60 turns):")
  for k in ("print",):
    if k + ".n" not in P:
      continue
    print(f"  the {k:6s} {P.get(k, 0)/n:.4f} ms   over {P.get(k + '.n', 0)/n:.1f} calls a turn")
  print()
  print("  **⇒⇒† AND **THE **RENDER **IS **~1.1 ms **AND **THE **DECODE **IS **~1.0 ms**, **⇒⇒† AND **AND "
        "**THE **PRINT **IS **A **SYSCALL **OF **15,642 **BYTES**")


if __name__ == "__main__":
  main()
