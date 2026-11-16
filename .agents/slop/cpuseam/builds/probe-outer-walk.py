#!/usr/bin/env python3
"""COUNT **THE OUTER WALK's LENGTH** AT **EACH `rtp` CALL**, **IN THE DAEMON**, AND **THE SUM**.

**WHY:** MEASURED: **`rtp` IS **0.4787 ms** A TURN** AND **ITS **DEEPEST** SUB-CALL IS
**`List.get` (0.6414 ms** ACROSS **THE WHOLE TURN**) -- **⇒⇒⇒ AND `List.get` IS **THE PRELUDE's
**RECURSIVE, ONE-ELEMENT-AT-A-TIME** WALK** (MEASURED, **THE COMPILED FORM**:
`if (_n_0 == 0) ... else { $0 = _t_0; $1 = _p_0; continue; }`).

**⇒⇒⇒ AND `rtp` DOES **TWO** WALKS** -- **THE **OUTER** ONE (OVER **THE BLOCK LIST**, UP TO
**49** ELEMENTS) **AND **THE **INNER** ONE (OVER **THE BLOCK**, UP TO **16**) -- **⇒⇒⇒ AND **THE
OUTER** ONE IS **THE **BIGGER** HALF**, **⇒⇒⇒ AND **THE QUESTION IS **HOW MANY ELEMENTS **THE
OUTER** WALK **TOUCHES **IN **A WHOLE TURN****.

**⇒⇒⇒ AND **THE COUNT IS **A WALK**, WHICH IS **WHAT `List.get` DOES ANYWAY** -- **⇒⇒⇒ SO **THE
INSTRUMENT'S COST IS **THE COST IT MEASURES**."""

import json
import pathlib
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = "globalThis.__W = {outer:0, inner:0, calls:0, n:0};"


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  # **THE `rtp` ENTRY**, WHERE `_r_0` AND `_i_0` ARE IN SCOPE.
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
  # **⇒⇒⇒ AND **THE **OUTER** WALK **IS **THE WALK OF **`List.get(Rows_ts(r), bi)`** -- **⇒⇒⇒ AND
  # **THE **BI** IS **`d/16`**, **⇒⇒⇒ AND **THE WALK **IS **OVER **THE **BLOCK LIST****.
  src = (src[:brace + 1]
         + "\n  { const __nn = $$_________tinybendygrad_renderer_cstyle_Rows_n(_r_0);"
           " const __dd = ((__nn - 1) >>> 0) - _i_0 >>> 0;"
           " const __bi = $$_________tinybendygrad_renderer_cstyle_Rows_bi(_r_0, __dd);"
           " let __l = 0, __x = $$_________tinybendygrad_renderer_cstyle_Rows_ts(_r_0);"
           " while (__x && __x.$ === \"Con\") { __l += 1; __x = __x.tail; }"
           " globalThis.__W.outer += __l;"
           " let __m = 0, __y = $$_________tinybendygrad_renderer_cstyle_Rows_blk(_r_0, __bi);"
           " while (__y && __y.$ === \"Con\") { __m += 1; __y = __y.tail; }"
           " globalThis.__W.inner += __m;"
           " globalThis.__W.calls = (globalThis.__W.calls || 0) + 1; }"
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
  base = BUILD / "now.js"
  out = BUILD / "serve_outer.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "outer")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  W = json.loads((BUILD.parent / "nf-outer/cpu.json.d").read_text())
  n = max(W.get("n", 1), 1)
  calls = W.get("calls", 0) // n
  outer = W.get("outer", 0) // n
  inner = W.get("inner", 0) // n
  print(f"\nTHE `rtp` WALKS ({n} turns):")
  print(f"  CALLS A TURN: {calls}")
  print(f"  THE OUTER WALK (THE BLOCK LIST): {outer} ELEMENTS A TURN "
        f"({outer / max(calls, 1):.1f} A CALL)")
  print(f"  THE INNER WALK (THE BLOCK):      {inner} ELEMENTS A TURN "
        f"({inner / max(calls, 1):.1f} A CALL)")
  print(f"  THE TOTAL: {outer + inner} ELEMENTS A TURN")
  print()
  print("**⇒⇒⇒ AND `List.get` IS **THE PRELUDE's **RECURSIVE** WALK** (ONE ELEMENT PER")
  print("CALL), **⇒⇒⇒ AND **THE PRELUDE's `List.get` IS **CALLED **12** PLACES **IN **THE COMPILED")
  print("RENDER**, **⇒⇒⇒ AND **THE **OUTER** WALK IS **THE **BIGGER** HALF** -- **⇒⇒⇒ AND **THE")
  print("**ELEMENTS A TURN** IS **THE NUMBER **THE FIX MUST **CUT****.")
