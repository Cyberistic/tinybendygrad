#!/usr/bin/env python3
"""**THE **CEILING **OF **THE **`List.concat` **FIX**, **MEASURED **BY **BREAKING **IT** -- **⇒⇒† AND
**AND **THIS **IS **NOT **A **FIX**, **IT **IS **THE **MEASUREMENT **THAT **DECIDES **WHETHER **A
**FIX **IS **WORTH **MAKING**.

**THE **METHOD.** THE **COMPILED **FORM's **`List.concat`** **IS **REPLACED **BY **A **VERSION **THAT
**DOES **NOT **COPY** -- **⇒⇒† AND **AND **THE **OUTPUT **IS **WRONG **ON **PURPOSE** (⇒⇒† AND **AND
**THE **POINT **IS **THE **TIMING**) -- **⇒⇒† AND **AND **THE **RENDER's **WALL **IS **MEASURED
**AGAINST **THE **BASELINE** (⇒⇒† AND **AND **THE **DELTA **IS **THE **CEILING**)**, **⇒⇒† AND **AND
**THE **PATCH **IS **IN **THE **COMPILED **FORM **AND **NOT **IN **THE **SUBSTRATE** (⇒⇒† AND **AND
**SO **NOTHING **IS **COMMITTED**)**.
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
  """**`List.concat` **WITHOUT **THE **COPY** -- **⇒⇒† AND **THE **COMPILED **FORM's **BODY **IS
  **`List.append(a, A, h, List.concat(a, A, t))`**, **⇒⇒† AND **AND **THE **COPY **IS **INSIDE
  **`List.append`**, **⇒⇒† AND **AND **SO **THE **CEILING **IS **MEASURED **BY **REPLACING **THE
  **`List.append`** **WITH **A **VERSION **THAT **DOES **NOT **COPY** (⇒⇒† AND **AND **THE **OUTPUT
  **IS **WRONG**, **⇒⇒† AND **AND **THAT **IS **THE **POINT**)**."""
  i, end = find_fn(src, "$List_append")
  new = """function $List_append(_xs_0, _ys_0) {
  if (_xs_0.$ === "Nil") {
    return _ys_0;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": $$List_append(_t_0, _ys_0)};
  }
}"""
  return src[:i] + new + src[end:]


def build(name: str, s: str) -> pathlib.Path:
  s = s.replace(WALL_OLD, WALL_NEW).replace(DUMP_OLD, DUMP_NEW)
  p = BUILD / name
  p.write_text(s)
  return p


def main():
  base = BUILD / "serve_plus.js"
  src = base.read_text()
  a = build("serve_cc_base.js", src)
  b = build("serve_cc_fast.js", patch(src))
  da = noisefloor.Daemon(a, "ccbase")
  db = noisefloor.Daemon(b, "ccfast")
  dc = noisefloor.Daemon(build("serve_cc_noise.js", src), "ccnoise")
  da.start()
  db.start()
  dc.start()
  time.sleep(1.2)
  for _ in range(120):
    da.turn()
    db.turn()
    dc.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()
  dc.stop()

  def walls(tag):
    p = pathlib.Path(str(BUILD.parent / f"nf-{tag}" / "cpu.json") + ".w")
    return sorted(w["w"] for w in json.loads(p.read_text()).get("W", []))

  A, B, C = walls("ccbase"), walls("ccfast"), walls("ccnoise")
  print()
  print("THE **RENDER's **WALL**, **THE **BASELINE**, **THE **`List.append` **WITHOUT **THE **COPY**, "
        "**AND **THE **NOISE **FLOOR**:")
  print("  A (the baseline):        min %.4f  median %.4f" % (A[0], A[len(A) // 2]))
  print("  B (no copy):             min %.4f  median %.4f" % (B[0], B[len(B) // 2]))
  print("  C (the noise floor):     min %.4f  median %.4f" % (C[0], C[len(C) // 2]))
  print()
  print("  **THE **CEILING**: the minima %.4f   the medians %.4f"
        % (B[0] / A[0], B[len(B) // 2] / A[len(A) // 2]))
  print("  **AND **THE **NOISE **FLOOR**: the minima %.4f   the medians %.4f"
        % (C[0] / A[0], C[len(C) // 2] / A[len(A) // 2]))


if __name__ == "__main__":
  main()
