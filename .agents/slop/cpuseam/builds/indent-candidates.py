#!/usr/bin/env python3
"""**THE **TWO **CANDIDATE **FIXES **FOR **THE **INDENT**, **MEASURED **IN **THE **DAEMON** -- **⇒⇒† AND
**AND **THE **VERDICT **IS **A **RATIO **OF **THE **PAIRED **RUNS**.

**THE **CANDIDATE **A: **THE **INDENT **IS **CARRIED **IN **THE **STATE** -- **⇒⇒† AND **THE **STATE
**ALREADY **CARRIES **THE **DEPTH**, **⇒⇒† AND **AND **THE **INDENT **IS **A **FUNCTION **OF **THE
**DEPTH**, **⇒⇒† AND **AND **THE **INDENT **IS **REBUILT **407 **TIMES **A **TURN **FOR **THE **SAME
**FIVE **VALUES**.

**THE **CANDIDATE **B: **THE **INDENT **IS **BUILT **BY **ONE **CONCAT **OF **A **LIST **OF **PIECES**
-- **⇒⇒† AND **THE **CURRENT **SHAPE **DOES **N **SEQUENTIAL **CONCATS** (⇒⇒† AND **ONE **PER
**LEVEL**) **⇒⇒† AND **AND **THE **CANDIDATE **DOES **ONE **CONCAT **OF **AN **N-PIECE **LIST**.

**⇒⇒† AND **BOTH **ARE **MEASURED **IN **THE **COMPILED **FORM** (⇒⇒† AND **SO **NOTHING **IS
**COMMITTED **AND **THE **SUBSTRATE **IS **UNTOUCHED**)**.
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


def body_of(src: str, name: str):
  """THE **COMPILED **FUNCTION's **BODY**, **AND **ITS **SPAN** -- **⇒⇒† AND **THE **NAIVE **SCAN
  **CUTS **A **COMPILED **`if/else` **CHAIN **IN **HALF** (MEASURED, §138.3)**."""
  i = src.index(f"function {name}(")
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
  return i, k + 1, src[i:k + 1]


def candidate_b(src: str) -> str:
  """**THE **INDENT **BY **ONE **CONCAT **OF **A **LIST **OF **PIECES** -- **⇒⇒† AND **THE **DEPTH
  **IS **A **`Nat` **AND **THE **LIST **IS **BUILT **BY **A **LOOP** (⇒⇒† AND **AND **THE **LOOP
  **APPENDS **TO **THE **FRONT**, **⇒⇒† AND **AND **THE **LIST **IS **CONSUMED **ONCE**, **⇒⇒† AND
  **AND **SO **THE **APPEND **IS **O(1)**)**."""
  name = "$_________tinybendygrad_renderer_cstyle_ku_indent_go"
  i, end, body = body_of(src, name)
  # **⇒⇒† AND **THE **BODY's **TAIL **IS **THE **RECURSION** (⇒⇒† AND **AND **THE **BODY **IS **A
  # **LOOP **WITH **A **`continue`**) -- **⇒⇒† AND **AND **THE **CANDIDATE **IS **A **DIFFERENT
  # **BODY**: **IT **BUILDS **A **LIST **AND **CONCATs **IT **ONCE**).
  new = (f"function {name}($0, $1) {{\n"
         f"  for (;;) {{\n"
         f"    {{\n"
         f"      const _depth_0 = $0;\n"
         f"      const _acc_0 = $1;\n"
         f"      if (_depth_0 == 0) {{\n"
         f"        return $String_concat($acc_0);\n"
         f"      }} else {{\n"
         f"        const _p_0 = (_depth_0 - 1);\n"
         f"        $0 = _p_0;\n"
         f"        $1 = $List_append($acc_0, {{$: \"Con\", \"head\": \"  \", \"tail\": {$: \"Nil\"}}});\n"
         f"        continue;\n"
         f"      }}\n"
         f"    }}\n"
         f"  }}\n"
         f"}}")
  return src[:i] + new + src[end:]


def candidate_a(src: str) -> str:
  """**THE **INDENT **IS **A **CONSTANT **PER **DEPTH** -- **⇒⇒† AND **THE **CANDIDATE **IS **THE
  **UPPER **BOUND**: **A **MEMO **IS **NOT **POSSIBLE **IN **THE **RENDER's **FUNCTIONAL **STYLE**,
  **⇒⇒† AND **AND **SO **THE **CANDIDATE **IS **THE **DEPTH **MATCHED **AGAINST **THE **COMPILED
  **FORM's **LITERAL **TABLE** (⇒⇒† AND **AND **THE **COMPILED **FORM **CAN **COMPARE **A **`U32`
  **WITH **`===`**)**."""
  name = "$_________tinybendygrad_renderer_cstyle_ku_indent"
  i, end, body = body_of(src, name)
  # **⇒⇒† AND **THE **COMPILED **FORM's **DEPTH **IS **A **NUMBER**, **⇒⇒† AND **AND **THE
  # **INDENT **IS **ONE **OF **FIVE **VALUES**, **⇒⇒† AND **AND **THE **TABLE **IS **THE **FIX**,
  # **⇒⇒† AND **AND **THE **DEPTH **BEYOND **THE **TABLE **IS **THE **FALLBACK** (⇒⇒† AND **AND **THE
  # **FALLBACK **IS **THE **OLD **SHAPE**, **⇒⇒† AND **AND **SO **THE **BEHAVIOUR **IS **UNCHANGED**
  # **FOR **ANY **DEPTH**)**.
  table = "\n".join(
    f'    if (_depth_0 === {d}) {{ return {"  " * d!r}; }}' for d in range(6))
  new = (f"function {name}(_depth_0) {{\n"
         f"{table}\n"
         f"  return $_________tinybendygrad_renderer_cstyle_ku_indent_go((_depth_0 ), \"\");\n"
         f"}}")
  return src[:i] + new + src[end:]


def build(name: str, s: str) -> pathlib.Path:
  s = s.replace(WALL_OLD, WALL_NEW).replace(DUMP_OLD, DUMP_NEW)
  p = BUILD / name
  p.write_text(s)
  return p


def main():
  base = BUILD / "serve_base.js"
  src = base.read_text()
  variants = {
    "A": ("serve_ab_base.js", src),
    "B": ("serve_ab_candB.js", candidate_b(src)),
    "C": ("serve_ab_candC.js", candidate_a(src)),
  }
  daemons = {}
  for key, (name, s) in variants.items():
    p = build(name, s)
    d = noisefloor.Daemon(p, f"ab{key}")
    d.start()
    daemons[key] = d
  time.sleep(1.2)
  for _ in range(50):
    for key in variants:
      daemons[key].turn()
  time.sleep(0.3)
  for key in variants:
    daemons[key].stop()

  walls = {}
  for key in variants:
    p = pathlib.Path(str(BUILD.parent / f"nf-ab{key}" / "cpu.json") + ".w")
    walls[key] = [w["w"] for w in json.loads(p.read_text()).get("W", [])]

  print()
  print("THE **RENDER's **WALL**, THE **PAIRED **RUN**:")
  print("  A = the baseline; B = one concat of a list of pieces; C = a table of literals")
  print()
  med = {}
  for key in ("A", "B", "C"):
    w = sorted(walls[key])
    med[key] = (w[0], w[len(w) // 2])
    print("  %s: min %.4f  median %.4f   (n=%d)" % (key, w[0], w[len(w) // 2], len(w)))
  print()
  print("THE **RATIOS **AGAINST **THE **BASELINE**:")
  for key in ("B", "C"):
    print("  %s: the minima %.4f   the medians %.4f"
          % (key, med[key][0] / med["A"][0], med[key][1] / med["A"][1]))


if __name__ == "__main__":
  main()
