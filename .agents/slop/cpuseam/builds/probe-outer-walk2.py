#!/usr/bin/env python3
"""THE **OUTER **WALK's LENGTH** AT **EACH `rtp` CALL**, **FOR **ANY **BUILD**, **AND **THE **SUM**.

**THE **INSTRUMENT **IS **THE **PRELUDE's **WALK **COUNTED** -- **⇒⇒⇒ AND **THE **COUNT **IS **THE
**COST** (§138.5: **THE COUNT IS NOT THE COST** -- **BUT **THE **COUNT **IS **THE **WALK**, **⇒⇒⇒ AND
**THE **WALK **IS **WHAT `List.get` **DOES**)****.

**THE **ARITHMETIC **IS **READ **FROM **THE **BUILD** -- **⇒⇒⇒ AND **THE **PROBE **USES **THE
**BUILD's **OWN `Rows_bi`**, **⇒⇒⇒ AND **SO **IT **MEASURES **THE **BUILD **AND **NOT **A **MODEL
**OF **IT** -- **⇒⇒⇒ AND **THE **`rtp` **CALL **PASSES **THE **INDEX **THE **BUILD **USES**
(**THE **BASE **PASSES **`n-1-i`** **AND **THE **FORWARD **PASSES **`i`**)**, **⇒⇒⇒ AND **SO **THE
**PROBE **READS **WHICH **FORM **IS **IN **THE **COMPILED **CODE** **AND **USES **THAT**.
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


def instrument(src: str, rev: bool) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, "globalThis.__W = {outer:0, inner:0, calls:0, n:0};\n" + old, 1)

  site = "function $_________tinybendygrad_renderer_cstyle_rtp("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the rtp site is {src.count(site)}")
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
  # **⇒⇒⇒ AND **THE **INDEX **THE **BUILD **USES** -- **⇒⇒⇒ AND **THE **BASE **USES
  # **`n-1-i`** (THE **COMPILED **`rtp` **DOES **`Rows_get(r, ((n-1) - i))`**) **AND **THE
  # **FORWARD **USES **`i`** -- **⇒⇒⇒ AND **SO **THE **PROBE **TESTS **THE **COMPILED **`rtp`
  # **BODY** **FOR **THE **REVERSE **FORM** **AND **USES **WHICHEVER **IT **FINDS**.**
  revlit = "true" if rev else "false"
  revlit = "true" if rev else "false"
  probe = (
    "\n  { const __rev = " + revlit + ";"
    " const __nn = $$_________tinybendygrad_renderer_cstyle_Rows_n(_r_0);"
    " const __d = __rev ? (((__nn - 1) >>> 0) - _i_0) >>> 0 : _i_0;"
    " const __bi = $$_________tinybendygrad_renderer_cstyle_Rows_bi(_r_0, __d);"
    " let __l = 0, __x = $$_________tinybendygrad_renderer_cstyle_Rows_ts(_r_0);"
    " let __k = __bi;"
    " while (__x && __x.$ === \"Con\" && __k > 0) { __l += 1; __k -= 1; __x = __x.tail; }"
    " globalThis.__W.outer += __l;"
    " globalThis.__W.rev = __rev ? 1 : 0;"
    " globalThis.__W.h = globalThis.__W.h || {};"
    " globalThis.__W.h[__l] = (globalThis.__W.h[__l] || 0) + 1;"
    " let __m = 0, __y = $$_________tinybendygrad_renderer_cstyle_Rows_blk(_r_0, __bi);"
    " while (__y && __y.$ === \"Con\") { __m += 1; __y = __y.tail; }"
    " globalThis.__W.inner += __m;"
    " globalThis.__W.calls = (globalThis.__W.calls || 0) + 1; }")
  src = src[:brace + 1] + probe + src[brace + 1:]

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
  out = BUILD / f"ow_{tag}.js"
  txt = js.read_text()
  rev = "Rows_get(_r_0, ((" in txt and "_i_0) >>> 0))" in txt
  out.write_text(instrument(txt, rev))
  d = noisefloor.Daemon(out, f"ow{tag}")
  d.start()
  time.sleep(0.8)
  for _ in range(20):
    d.turn()
  d.stop()
  W = json.loads((BUILD.parent / f"nf-ow{tag}/cpu.json.d").read_text())
  n = max(W.get("n", 1), 1)
  calls = W.get("calls", 0) // n
  outer = W.get("outer", 0) // n
  inner = W.get("inner", 0) // n
  h = {int(k): v // n for k, v in W.get("h", {}).items()}
  return {"rev": W.get("rev", 0), "calls": calls, "outer": outer, "inner": inner, "h": h}


if __name__ == "__main__":
  for js in sys.argv[1:]:
    r = measure(BUILD / js, js.replace(".js", "").replace("_", ""))
    print(f"\n=== {js} === (the reverse index: {bool(r['rev'])})")
    print(f"  CALLS A TURN: {r['calls']}")
    print(f"  THE OUTER WALK: {r['outer']} ELEMENTS A TURN ({r['outer'] / max(r['calls'], 1):.1f} A CALL)")
    print(f"  THE INNER WALK: {r['inner']} ELEMENTS A TURN ({r['inner'] / max(r['calls'], 1):.1f} A CALL)")
    print(f"  THE TOTAL: {r['outer'] + r['inner']} ELEMENTS A TURN")
    print(f"  THE OUTER WALK's LENGTH, AS A HISTOGRAM (ELEMENTS -> CALLS A TURN):")
    for k in sorted(r["h"], reverse=True)[:8]:
      print(f"    {k:4d} elements -> {r['h'][k]:6d} calls")
    print("    ...")
    for k in sorted(r["h"])[:6]:
      print(f"    {k:4d} elements -> {r['h'][k]:6d} calls")
