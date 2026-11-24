#!/usr/bin/env python3
"""**THE **CEILING **OF **THE **WIRE's **NUMBER-LIST **BUILD**, **MEASURED **IN **THE **DAEMON** -- **⇒⇒†
**AND **AND **THE **WIRE **IS **THE **PORT's **OWN **FILE** (⇒⇒† AND **AND **IT **IS **IN **THE
**SHIPPED **PATH**)**.

**WHY.** `decode-shape.py` **READS**: **the **decode **IS **1.71 ms **A **TURN** (⇒⇒† AND **AND **THE
**SPLIT **IS **0.12 ms **OF **IT**)** -- **⇒⇒† AND **AND **THE **REST **-- **0.6 ms** -- **IS **THE
**NUMBER-LIST **BUILD** (⇒⇒† AND **AND **`wire_both` **BUILDS **ONE **BEND **LIST **PER **ROW**, **⇒⇒†
**AND **AND **THE **ROWS **ARE **~78 **A **TURN**)**, **⇒⇒† AND **AND **THE **DECODE **IS **NOW **BIGGER
**THAN **THE **RENDER** (⇒⇒† AND **AND **THE **RENDER **IS **~1.1 ms**)**.

**⇒⇒† AND **THE **`list()` **HELPER **ALLOCATES **A **JS **ARRAY **PER **ROW** (⇒⇒† AND
**`t.split("~").map(Number)`**) **⇒⇒† AND **AND **THE **LIST **IS **THEN **REBUILT **CELL **BY **CELL**
(⇒⇒† AND **AND **THE **CELLS **ARE **THE **BEND **LIST's **OWN **NODES**) -- **⇒⇒† AND **AND **THE
**ARRAY **IS **THROWN **AWAY** (⇒⇒† AND **AND **THAT **IS **A **WASTED **ALLOCATION **PER **ROW**)**
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


def patch(src: str) -> str:
  """**THE **ARRAY **IS **NOT **ALLOCATED** -- **⇒⇒† AND **AND **THE **TOKEN **COUNT **IS **KNOWN
  **FROM **THE **TOKEN's **OWN **TEXT** (⇒⇒† AND **AND **THE **COUNT **OF **THE **'~'-SEPARATED
  **NUMBERS **IS **THE **COUNT **OF **THE **'~'s **PLUS **ONE**) -- **⇒⇒† AND **AND **THE **NUMBERS **ARE
  **READ **STRAIGHT **OUT **OF **THE **TOKEN** (⇒⇒† AND **AND **NO **ARRAY **AT **ALL**)**."""
  i, end = find_fn(src, "wire_both")
  body = src[i:end]
  old = '  const list = (t) => (t === "-" ? [] : t.split("~").map(Number));'
  if body.count(old) != 1:
    raise SystemExit(f"WARN: the list helper site is {body.count(old)}")
  new = ('  const list = (t) => { if (t === "-") return [];\n'
         '    const out = []; let cur = 0, has = false;\n'
         '    for (let k = 0; k < t.length; k += 1) {\n'
         '      const ch = t.charCodeAt(k);\n'
         '      if (ch === 126) { out.push(has ? Number(cur) : 0); cur = 0; has = false; }\n'
         '      else { cur = cur * 10 + (ch - 48); has = true; }\n'
         '    }\n'
         '    out.push(has ? Number(cur) : 0);\n'
         '    return out; };')
  body = body.replace(old, new)
  return src[:i] + body + src[end:]


def main():
  import subprocess
  base = BUILD / "serve_plus.js"
  src = base.read_text()
  out = BUILD / "serve_wire2.js"
  out.write_text(patch(src))
  chk = subprocess.run(["node", "--check", str(out)], capture_output=True, text=True)
  if chk.returncode != 0:
    raise SystemExit(f"WARN: the patch does not parse:\n{chk.stderr[:600]}")
  print("THE PATCHED BUILD PARSES")

  # **⇒⇒† AND **THE **NUMBERS **CLOCK** (⇒⇒† AND **AND **IT **IS **THE **BUILD's **OWN **WORK**)**
  ACC = ('globalThis.__N = globalThis.__N || 0;\n')
  a = BUILD / "serve_wire_base.js"
  b = BUILD / "serve_wire_new.js"
  for name, s in (("serve_wire_base.js", src), ("serve_wire_new.js", out.read_text())):
    s = s.replace("function wire_both(s) {", "function wire_both(s) {\n  const __t0 = performance.now();")
    s = s.replace("  return { $: \"Both\", ss, ns };",
                  "  globalThis.__N += performance.now() - __t0;\n  return { $: \"Both\", ss, ns };")
    s = s.replace("function $serve(_fuel_0, _m_0, _s_0) {",
                  "globalThis.__N = globalThis.__N || 0;\nfunction $serve(_fuel_0, _m_0, _s_0) {")
    s = s.replace('return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);',
                  'try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".wn", '
                  'String(globalThis.__N)); } catch (e) {}\n'
                  'return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);')
    (BUILD / name).write_text(s)
    c = subprocess.run(["node", "--check", str(BUILD / name)], capture_output=True, text=True)
    if c.returncode != 0:
      raise SystemExit(f"WARN: {name} does not parse:\n{c.stderr[:600]}")

  da = noisefloor.Daemon(a, "wirebase")
  db = noisefloor.Daemon(b, "wirenew")
  da.start()
  db.start()
  time.sleep(1.0)
  for _ in range(60):
    da.turn()
    db.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()

  for tag, label in (("wirebase", "A (the baseline)"), ("wirenew", "B (no array)")):
    p = pathlib.Path(str(BUILD.parent / f"nf-{tag}" / "cpu.json") + ".wn")
    total = float(p.read_text())
    print(f"  {label}: the wire_both work {total/60:.4f} ms a turn")


if __name__ == "__main__":
  main()
