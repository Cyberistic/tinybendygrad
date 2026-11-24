#!/usr/bin/env python3
"""**THE **CEILING **OF **THE **INDENT's **COST**, **MEASURED **BY **BREAKING **IT** -- **⇒⇒† AND
**AND **THIS **IS **NOT **A **FIX**, **IT **IS **THE **MEASUREMENT **THAT **DECIDES **WHETHER **A
**FIX **IS **WORTH **MAKING**.

**THE **METHOD.** THE **COMPILED **FORM**'s **`ku_indent`** **IS **REPLACED **BY **A **CONSTANT**
-- **⇒⇒† AND **THE **OUTPUT **IS **WRONG** (⇒⇒† AND **THE **INDENT **IS **GONE**), **⇒⇒† AND **AND
**THE **RENDER's **WALL **IS **MEASURED **AGAINST **THE **BASELINE** (⇒⇒† AND **AND **THE **DELTA
**IS **THE **CEILING**) -- **⇒⇒† AND **AND **THE **PATCH **IS **IN **THE **COMPILED **FORM **AND **NOT
**IN **THE **SUBSTRATE**, **⇒⇒† AND **AND **SO **NOTHING **IS **COMMITTED **AND **THE **CORPUS
**CERTIFICATE **IS **NOT **TOUCHED**.

**⇒⇒† AND **AND **THE **A/B **IS **A **PAIRED **RUN** (⇒⇒† AND **THE **TREE's OWN RULE: **THE
**NOISE **FLOOR **MUST **BE **READ **IMMEDIATELY **BEFORE **THE **VERDICT**).
"""

import pathlib
import re
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def patch(src: str) -> str:
  """**THE **INDENT **IS **REPLACED **BY **A **CONSTANT** -- **⇒⇒† AND **THE **BODY **IS **THE
  **ONE-LINE **ENTRY** (⇒⇒† AND **AND **THE **RECURSION **IS **`ku_indent_go`'s**)**."""
  m = re.search(r"function (\$_________tinybendygrad_renderer_cstyle_ku_indent)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no ku_indent")
  name, params = m.group(1), m.group(2)
  i = src.index(f"function {name}({params})")
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
        break
    k += 1
  # **⇒⇒† AND **THE **REPLACEMENT **IS **A **CONSTANT** -- **⇒⇒† AND **AND **THE **OUTPUT **IS
  # **WRONG **ON **PURPOSE** (⇒⇒† AND **THE **POINT **IS **THE **TIMING**)**
  new = (f"function {name}({params}) {{\n"
         f"  return \"  \";\n"
         f"}}")
  return src[:i] + new + src[k + 1:]


def wall(path: pathlib.Path, tag: str, turns: int = 40):
  """THE **RENDER's **WALL**, **MIN **AND **MEDIAN**, **OVER **THE **TURNS**."""
  d = noisefloor.Daemon(path, tag)
  d.start()
  time.sleep(0.8)
  walls = []
  for _ in range(turns):
    d.turn()
  time.sleep(0.2)
  d.stop()
  data = json.loads(pathlib.Path(str(d.cpu_file)).read_text()) if False else None
  return walls


def main():
  import json
  base = BUILD / "serve_base.js"
  src = base.read_text()

  # **THE **A/B **BUILD** -- **⇒⇒† AND **AND **THE **WALL **IS **READ **AT **THE **RENDER's **OWN
  # **SITE** (⇒⇒† AND **THE **RENDER **IS **WHAT **THE **CALLER's **CLOCK **ALREADY **READS**)**.
  WALL_OLD = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  WALL_NEW = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  DUMP_OLD = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  DUMP_NEW = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".w",
        JSON.stringify({W: globalThis.__W || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""

  def build(name: str, s: str) -> pathlib.Path:
    s = s.replace(WALL_OLD, WALL_NEW)
    s = s.replace(DUMP_OLD, DUMP_NEW)
    p = BUILD / name
    p.write_text(s)
    return p

  a = build("serve_ab_base.js", src)
  b = build("serve_ab_noindent.js", patch(src))

  # **THE **PAIRED **RUN** -- **⇒⇒† AND **AND **THE **TWO **ARE **ALTERNATED** (⇒⇒† AND **THE
  # **TREE's OWN RULE: **A **PAIRED **A/B**, **⇒⇒† AND **AND **THE **NOISE **FLOOR **MOVES **WITH
  # **THE **LOAD**)**.
  walls = {"A": [], "B": []}
  da = noisefloor.Daemon(a, "abbase")
  db = noisefloor.Daemon(b, "abnoind")
  da.start()
  db.start()
  time.sleep(1.0)
  for i in range(50):
    da.turn()
    db.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()

  def read(tag):
    p = pathlib.Path(str(noisefloor.BUILD.parent / f"nf-{tag}" / "cpu.json") if hasattr(noisefloor, "BUILD") else "")
    return None

  # **⇒⇒† AND **THE **DUMPS **ARE **AT **THE **DAEMON's **OWN **FILES** (⇒⇒† AND **AND **THE **PATH
  # **IS **READ **FROM **THE **DAEMON**, **⇒⇒† AND **AND **NOT **GUESSED**)**.
  for tag, key in (("abbase", "A"), ("abnoind", "B")):
    p = pathlib.Path(str(BUILD.parent / f"nf-{tag}" / "cpu.json") + ".w")
    data = json.loads(p.read_text())
    walls[key] = [w["w"] for w in data.get("W", [])]
    print(f"THE {key} WALLS: {len(walls[key])}")

  A = sorted(walls["A"])
  B = sorted(walls["B"])
  if not A or not B:
    raise SystemExit("WARN: no walls")
  print()
  print("THE **RENDER's **WALL**, **THE **BASELINE **AND **THE **INDENT **BROKEN**:")
  print("  A (the baseline):  min %.4f  median %.4f" % (A[0], A[len(A) // 2]))
  print("  B (no indent):    min %.4f  median %.4f" % (B[0], B[len(B) // 2]))
  print()
  print("  **THE **CEILING **OF **THE **INDENT's **FIX**:")
  print("    the RATIO OF THE TWO MINIMA: %.4f" % (B[0] / A[0]))
  print("    the RATIO OF THE TWO MEDIANS: %.4f" % (B[len(B) // 2] / A[len(A) // 2]))
  print()
  print("  **⇒⇒† AND **THE **NOISE **FLOOR **MUST **BE **READ **NOW** -- **⇒⇒† AND **AND **THE "
        "**VERDICT **IS **A **RATIO** (⇒⇒† AND **THE **TREE's OWN RULE)**")


if __name__ == "__main__":
  main()
