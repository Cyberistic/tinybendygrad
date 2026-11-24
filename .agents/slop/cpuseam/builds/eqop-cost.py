#!/usr/bin/env python3
"""**THE **COST **OF **THE **`eq_op` **DISPATCH**, **MEASURED **IN **THE **DAEMON** -- **⇒⇒† AND **AND
**THE **ARM **COUNT **IS **A **COUNT **AND **NOT **THE **COST** (⇒⇒† AND **AND **§138's **LESSON
**SAYS **SO**)**.

**WHY.** `cstyle.bend:1247`: **`def eq_op(x: O.Op, y: O.Op) -> Bool:`** **IS **A **76-ARM **`===`
**CHAIN **ON **THE **OP **TAG** -- **⇒⇒† AND **AND **§138's **COMMENT **RECORDS **"30,640
**`Ops.value` **calls **and **15,320 **`O.eq_op` **calls **a **turn"** (⇒⇒† AND **AND **THAT **IS **ON
**THE **782-UOP **WIRE**, **⇒⇒† AND **AND **THE **WIRE **CARRIES **FIVE **KERNELS**)**.

**⇒⇒† AND **AND **THE **RENDER **CALLs **`eq_op` **FROM **`ku_alu_srcs`** (⇒⇒† AND **AND **ONCE **PER
**SOURCE**, **⇒⇒† AND **AND **THE **ALU **IS **THE **BIGGEST **LEAF **INSIDE **THE **`text`
**FAMILY**) -- **⇒⇒† AND **AND **SO **THE **DISPATCH **IS **THE **NEXT **TARGET**.

**⇒⇒† AND **THIS **INSTRUMENT **CLOCKS **THE **`eq_op` **BODY** (⇒⇒† AND **AND **THE **CLOCK **IS
**INSIDE**, **⇒⇒† AND **AND **THE **TREE's OWN **RULE**) **AND **COUNTS **THE **CALLS** (⇒⇒† AND **AND
**THE **COUNT **IS **THE **MULTIPLIER**)**
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

ACC = """globalThis.__E = globalThis.__E || {};
globalThis.__EM = (t0) => { globalThis.__E.t = (globalThis.__E.t || 0) + (performance.now() - t0); };
globalThis.__EN = () => { globalThis.__E.n = (globalThis.__E.n || 0) + 1; };"""


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
  # **THE **`eq_op` **BODY** -- **⇒⇒† AND **AND **THE **COMPILED **NAME** (⇒⇒† AND **AND **THE
  # **NAME **IS **WHAT **THE **PATCH **MATCHES**)**.
  m = re.search(r"function (\$[A-Za-z0-9_]*eq_op[a-zA-Z0-9_]*)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no eq_op")
  fname, params = m.group(1), m.group(2)
  i, end = find_fn(src, fname)
  body = src[i:end]
  inner = fname + "__orig"
  body = body.replace(f"function {fname}(", f"function {inner}(", 1)
  args = ", ".join(p.strip() for p in params.split(","))
  wrapper = (f"function {fname}({params}) {{\n"
             f"  const __t = performance.now();\n"
             f"  globalThis.__EN();\n"
             f"  const __v = {inner}({args});\n"
             f"  globalThis.__EM(__t);\n"
             f"  return __v;\n"
             f"}}")
  src = src[:i] + body + "\n" + wrapper + src[end:]
  print(f"THE CLOCKED FUNCTION: {fname}")

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".eq",
        JSON.stringify({E: globalThis.__E || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_eqop_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"eqop{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".eq").read_text())
  E = data.get("E", {})
  n = 60
  print()
  print(f"THE **`eq_op` **DISPATCH**, **IN THE DAEMON** ({n} turns):")
  print(f"  the CALLS a turn:  {E.get('n', 0)/n:.1f}")
  print(f"  the OWN WORK:     {E.get('t', 0)/n:.4f} ms")
  print(f"  **⇒⇒† AND **THE **PER-CALL **COST: **{(E.get('t', 0)/n)/(E.get('n', 0)/n)*1000:.3f} µs")


if __name__ == "__main__":
  main()
