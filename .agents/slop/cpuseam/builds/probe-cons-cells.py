#!/usr/bin/env python3
"""**THE **NUMBER **OF **CONS **CELLS **ALLOCATED **A **TURN**, **FOR **ANY **BUILD** -- **THE
**DEFINITIVE **WRITE **COST**.

**WHY:** §138.5: **THE COUNT IS NOT THE COST** -- **⇒⇒⇒ AND **HERE **THE COUNT **IS **THE **COST**,
**⇒⇒⇒ AND **THE **COUNT **IS **THE **LIST **CELLS **THE **PRELUDE **ALLOCATES**, **⇒⇒⇒ AND **A
**CONS **IS **A **CELL** (MEASURED: **THE **COMPILED **`List.append` **IS **`h <> List.append(a, A,
t, ys)`**, **⇒⇒⇒ AND **EVERY **CALL **ALLOCATES **ONE **CELL**)** -- **⇒⇒⇒ AND **SO **THE **COUNT
**OF **THE **CALLS **IS **THE **COUNT **OF **THE **CELLS**).

**THE **INSTRUMENT **IS **THE **`List.append` **AND **`List.set` **CALL **SITES**, **⇒⇒⇒ AND **IT
**COUNTS **THE **ARGUMENT **LIST **LENGTHS **TOO** (THE **`List.append` **THE **PORT **USES **IS
**THE **RECURSIVE **ONE**, **⇒⇒⇒ AND **SO **ITS **CELL **COUNT **IS **THE **LENGTH **OF **THE
**LIST **IT **COPIES**)**.
"""

import json
import pathlib
import re
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def instrument(src: str) -> str:
  """**⇒⇒⇒ AND **THE **COUNTS **ARE **TAKEN **AT **THE **`List_append` **AND **`List_set` **SITES**,
  **⇒⇒⇒ AND **THE **CELLS **ARE **COUNTED **FROM **THE **LIST's **LENGTH** -- **⇒⇒⇒ AND **THE
  **LENGTH **IS **COUNTED **AT **THE **SITE** (**THE **LIST **IS **IN **SCOPE**)**."""
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, "globalThis.__W = {n:0, app:0, appCells:0, set:0, setCells:0, byFn:{}};\n" + old, 1)

  # **⇒⇒⇒ AND **THE **`List_append` **CALL **SITES** -- **⇒⇒⇒ AND **THE **LENGTH **OF **THE **LIST
  # **BEING **COPIED** **IS **THE **CELL **COUNT** (THE **RECURSIVE **FORM)**.
  def add_probe(name: str, fn: str, cell_expr: str, key: str) -> None:
    nonlocal src
    site = f"function ${fn}("
    if src.count(site) != 1:
      raise SystemExit(f"WARN: the {fn} site is {src.count(site)}")
    op = src.index("(", src.index(site))
    d = 0
    for c in range(op, len(src)):
      if src[c] == "(":
        d += 1
      elif src[c] == ")":
        d -= 1
        if d == 0:
          cp = c
          break
    brace = src.index("{", cp)
    src = (src[:brace + 1]
           + ("\n  { let __len = 0; let __w = " + cell_expr + ";"
              " while (__w && __w.$ === \"Con\") { __len += 1; __w = __w.tail; }"
              " globalThis.__W." + key + " += 1; globalThis.__W." + key + "Cells += __len; }")
           + src[brace + 1:])

  # **THE **`List_append(a, A, xs, ys)` **COPIES **`xs`** -- **⇒⇒⇒ AND **SO **THE **CELLS **ARE
  # **`len(xs)`**.
  add_probe("append", "List_append", "$1", "app")
  # **THE **`List_set(xs, n, x)` **COPIES **THE **PREFIX **OF **THE **LIST **UP **TO **`n`** -- **⇒⇒⇒
  # **AND **SO **THE **CELLS **ARE **`n`** (AND **THE **WALK **IS **`n`**)**.
  add_probe("set", "List_set", "$0", "set")

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__W.n = (globalThis.__W.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__W || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


def measure(js: pathlib.Path, tag: str):
  out = BUILD / f"cc_{tag}.js"
  out.write_text(instrument(js.read_text()))
  d = noisefloor.Daemon(out, f"cc{tag}")
  d.start()
  time.sleep(0.8)
  for _ in range(20):
    d.turn()
  d.stop()
  W = json.loads((BUILD.parent / f"nf-cc{tag}/cpu.json.d").read_text())
  n = max(W.get("n", 1), 1)
  return {k: W.get(k, 0) // n for k in ("app", "appCells", "set", "setCells")}


if __name__ == "__main__":
  for js in sys.argv[1:]:
    tag = js.replace(".js", "").replace("_", "")
    r = measure(BUILD / js, tag)
    tot = r["appCells"] + r["setCells"]
    print(f"\n=== {js} ===")
    print(f"  List.append CALLS A TURN: {r['app']}   CELLS: {r['appCells']}")
    print(f"  List.set    CALLS A TURN: {r['set']}   CELLS: {r['setCells']}")
    print(f"  THE TOTAL CELLS ALLOCATED A TURN: {tot}")
