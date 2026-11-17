#!/usr/bin/env python3
"""**HOW **MANY **TIMES **`st_set.p` **FIRES**, **AND **AT **WHICH **BLOCK **INDICES** -- **AND **HOW
**MANY **CONS **`List.set` **WALKS **TO **GET **THERE**.

**WHY:** `st_set.p` **IS **THE **ONLY **CALLER **OF **THE **WRITE **INTO **AN **OLD **BLOCK** --
**⇒⇒⇒ AND **IN **THE **FORWARD **LAYOUT **THE **BLOCK **INDEX **IS **A **FORWARD **NUMBER**, **⇒⇒⇒
AND **SO **`List.set(ts, bi, ...)` **WALKS **`bi` **CONS** -- **⇒⇒⇒ AND **THE **QUESTION **IS **HOW
**MANY **CONS **THAT **IS** -- **⇒⇒⇒ AND **THE **ANSWER **IS **THE **DIFFERENCE **BETWEEN **THE
**TWO **LAYOUTS' **WRITE **COSTS**.
"""

import json
import pathlib
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, "globalThis.__W = {calls:0, walked:0, n:0, hist:{}};\n" + old, 1)

  site = "function $_________tinybendygrad_renderer_cstyle_st_set_p("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the st_set_p site is {src.count(site)}")
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
  # **⇒⇒⇒ AND **THE **BLOCK **INDEX **THE **BUILD **COMPUTES** -- **⇒⇒⇒ AND **THE **PROBE
  # **MEASURES **THE **WALK **`List.set` **ACTUALLY **DOES**, **⇒⇒⇒ AND **THAT **IS **THE
  # **NUMBER **THAT **MATTERS**.
  src = (src[:brace + 1]
         + "\n  { const __r = $$_________tinybendygrad_renderer_cstyle_St_r(_st_0);"
           " const __bi = $$_________tinybendygrad_renderer_cstyle_Rows_bi(__r, _i_0);"
           " let __l = 0, __x = $$_________tinybendygrad_renderer_cstyle_Rows_ts(__r);"
           " let __k = __bi;"
           " while (__x && __x.$ === \"Con\" && __k > 0) { __l += 1; __k -= 1; __x = __x.tail; }"
           " globalThis.__W.calls += 1; globalThis.__W.walked += __l;"
           " globalThis.__W.hist[__l] = (globalThis.__W.hist[__l] || 0) + 1; }"
         + src[brace + 1:])

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


if __name__ == "__main__":
  for js in sys.argv[1:]:
    out = BUILD / f"sp_{js.replace('.js','')}.js"
    out.write_text(instrument((BUILD / js).read_text()))
    d = noisefloor.Daemon(out, f"sp{js.replace('.js','').replace('_','')}")
    d.start()
    time.sleep(0.8)
    for _ in range(20):
      d.turn()
    d.stop()
    W = json.loads((BUILD.parent / f"nf-sp{js.replace('.js','').replace('_','')}/cpu.json.d").read_text())
    n = max(W.get("n", 1), 1)
    calls = W.get("calls", 0) // n
    walked = W.get("walked", 0) // n
    hist = {int(k): v // n for k, v in W.get("hist", {}).items()}
    print(f"\n=== {js} ===")
    print(f"  st_set.p CALLS A TURN: {calls}")
    print(f"  THE `List.set` WALK A TURN: {walked} cons")
    print(f"  THE WALK's LENGTH HISTOGRAM (CONS -> CALLS A TURN):")
    for k in sorted(hist, reverse=True)[:8]:
      print(f"    {k:4d} cons -> {hist[k]:6d} calls")
    for k in sorted(hist)[:4]:
      print(f"    {k:4d} cons -> {hist[k]:6d} calls")
