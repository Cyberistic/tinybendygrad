#!/usr/bin/env python3
"""**CLOCK **THE **LIST **BUILDERS**, **IN **THE **DAEMON** -- **⇒⇒† AND **AND **THE **`List.append`**
**COPIES **ITS **FIRST **ARGUMENT**, **⇒⇒† AND **AND **SO **AN **ACCUMULATOR **THAT **GROWS **IS
**O(n²)**.

**WHY.** `bend2/base.bend:1003`: **`def List.append(a, A, xs, ys)`** **DOES **`h <> List.append(a, A,
t, ys)`** -- **⇒⇒† AND **AND **SO **IT **COPIES **`xs`** (⇒⇒† AND **AND **THE **PORT's **OWN **COMMENT
**SAYS **SO**). **⇒⇒† AND **AND **THE **RENDER's **`st_kernel` **PREPENDS** (⇒⇒† AND **AND **SO **IT
IS **THE **O(1) **FORM**), **⇒⇒† AND **AND **THE **SITES **THAT **APPEND **TO **A **GROWING
**ACCUMULATOR **ARE **THE **QUADRATIC **ONES**, **⇒⇒† AND **AND **THIS **INSTRUMENT **SAYS **WHICH
**ONES **THOSE **ARE**.

**⇒⇒† AND **THE **CLOCKS **ARE **INSIDE **THE **FUNCTION **BODIES** (⇒⇒† AND **AND **THE **TREE's
**OWN **RULE**: **A **REST-ARGUMENTS **WRAPPER **IS **NOT **FREE**)**.
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

ACC = """globalThis.__L = globalThis.__L || {};
globalThis.__LM = (k, t0) => { globalThis.__L[k] = (globalThis.__L[k] || 0) + (performance.now() - t0); };
globalThis.__LN = (k) => { globalThis.__L[k + ".n"] = (globalThis.__L[k + ".n"] || 0) + 1; };"""


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


def instrument(src: str):
  # **THE **LIST **BUILDERS**, **BY **THEIR **COMPILED **NAME** -- **⇒⇒† AND **AND **THEY **ARE
  # **THE **PRELUDE's **OWN **FUNCTIONS** (⇒⇒† AND **AND **`List.append` **IS **THE **ONE **THAT
  # **COPIES**)**
  targets = {
    "list.append": "$List_append",
    "list.concat": "$List_concat",
    "list.reverse": "$List_reverse",
  }
  patched = {}
  for key, name in targets.items():
    m = re.search(r"function (" + re.escape(name) + r")\(([^)]*)\)\s*\{", src)
    if not m:
      continue
    fname, params = m.group(1), m.group(2)
    i, end = find_fn(src, fname)
    if i is None:
      continue
    body = src[i:end]
    # **THE **CLOCK **IS **AT **THE **ENTRY** -- **⇒⇒† AND **AND **THE **BODY **IS **KEPT
    # **VERBATIM** (⇒⇒† AND **AND **THE **RECURSION **IS **THE **BODY's **OWN**)**.
    inner = fname + "__inner"
    newbody = body.replace(f"function {fname}(", f"function {inner}(", 1)
    args = ", ".join(p.strip() for p in params.split(","))
    wrapper = (f"function {fname}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  const __v = {inner}({args});\n"
               f"  globalThis.__LM(\"{key}\", __t);\n"
               f"  globalThis.__LN(\"{key}\");\n"
               f"  return __v;\n"
               f"}}")
    src = src[:i] + newbody + "\n" + wrapper + src[end:]
    patched[key] = fname
  print(f"THE CLOCKED FUNCTIONS: {len(patched)}  ({', '.join(patched)})")

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  wall_old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  wall_new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  i = src.index(wall_old)
  src = src[:i] + wall_new + src[i + len(wall_old):]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".lb",
        JSON.stringify({L: globalThis.__L || {}, W: globalThis.__W || []})); } catch (e) {} }
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
  out = BUILD / f"serve_list_{base.stem}.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, f"list{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".lb").read_text())
  L = data.get("L", {})
  W = [w["w"] for w in data.get("W", [])]
  n = 60
  print()
  print("THE **RENDER's **LIST **WORK**, **IN THE DAEMON** (60 turns), ms a turn:")
  for key in ("list.append", "list.concat", "list.reverse"):
    if key + ".n" not in L:
      continue
    print(f"  {key:14s} {L.get(key, 0)/n:.4f} ms   over {L.get(key + '.n', 0)/n:.1f} calls a turn")
  if W:
    W.sort()
    print()
    print(f"  THE RENDER's WALL: min {min(W):.4f}  median {W[len(W)//2]:.4f}")


if __name__ == "__main__":
  main()
