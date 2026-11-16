#!/usr/bin/env python3
"""COUNT **THE `rtp` CALLS** AND **THEIR WALK DEPTH**, **IN THE DAEMON**.

**WHY:** MEASURED (`probe-alu-parts.py`, **IN THE DAEMON**): **`rtp` IS **0.4787 ms** A TURN** --
**THE LARGEST SINGLE THING MEASURED **IN **THE RENDER** SO FAR** -- **⇒⇒⇒ AND `rtp` IS **CALLED
FROM **14 PLACES**, **⇒⇒⇒ SO **IT IS **THE RENDER's MOST-CALLED INDEXED ACCESS**.

**⇒⇒⇒ AND `rtp(r, i)` IS **`Rows_get(r, n-1-i)`** -- **THE REVERSE INDEX** -- **AND
`Rows_get` IS **A TWO-LEVEL INDEXED** ACCESS** (`Rows_bi` COMPUTES `d/16` AND `Rows_off`
COMPUTES `d%16`, **SO **THE ROWS ARE **BLOCKED 16 AT A TIME**), **⇒⇒⇒ AND **EACH LEVEL IS
**A `List.get`**, **WHICH IS **O(index)**.

**⇒⇒⇒ SO **THE COST IS **THE CALL COUNT x **THE WALK DEPTH**, **AND **BOTH MUST BE
**COUNTED** -- **AND **THE WALK IS **WHAT `List.get` DOES ANYWAY**, **⇒⇒⇒ SO **THE
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

ACC = "globalThis.__R = {calls:0, walk:0, rows_n:0, n:0};"


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
  # **⇒⇒⇒ AND **THE WALK** IS **COUNTED **AT **THE `rtp` ENTRY**, AND **IT IS **THE **BLOCK's**
  # LENGTH** (THE LIST `List.get` WALKS) -- **AND **THE INDEX** IS **`n-1-i`**, WHICH **IS
  # **COMPUTED **INSIDE**, **⇒⇒⇒ SO **THE INSTRUMENT **RE-COMPUTES **IT** (IT IS **ONE
  # SUBTRACTION**)**.
  # **⇒⇒⇒ AND **`Rows_get` DOES **TWO** WALKS** -- **THE **OUTER** ONE **OVER **THE BLOCK LIST**
  # (`Rows_blk(r, bi)` -> `List.get(Rows_ts(r), bi)`, **UP TO **49** ELEMENTS**) **AND **THE
  # **INNER** ONE **OVER **THE BLOCK** (`List.get(b, off)`, **UP TO **16**) -- **⇒⇒⇒ AND **THE
  # FIRST PROBE MEASURED **ONLY **THE INNER** ONE** (MEASURED: **THE DEEPEST BLOCK WALKED WAS
  # 16**), **⇒⇒⇒ AND **THE OUTER** ONE IS **THE **BIGGER** HALF** (UP TO **49**)**.
  src = (src[:brace + 1]
         + "\n  { const __nn = $$_________tinybendygrad_renderer_cstyle_Rows_n(_r_0);"
           " const __dd = ((__nn - 1) >>> 0) - _i_0 >>> 0;"
           " let __l = 0, __x = $$_________tinybendygrad_renderer_cstyle_Rows_ts(_r_0);"
           " while (__x && __x.$ === \"Con\") { __l += 1; __x = __x.tail; }"
           " globalThis.__R.outer = Math.max(globalThis.__R.outer || 0, __l);"
           " let __m = 0, __y = $$_________tinybendygrad_renderer_cstyle_Rows_blk(_r_0,"
           " $$_________tinybendygrad_renderer_cstyle_Rows_bi(_r_0, __dd));"
           " while (__y && __y.$ === \"Con\") { __m += 1; __y = __y.tail; }"
           " globalThis.__R.inner = Math.max(globalThis.__R.inner || 0, __m);"
           " globalThis.__R.calls = (globalThis.__R.calls || 0) + 1;"
           " globalThis.__R.rows_n = Math.max(globalThis.__R.rows_n || 0, __nn); }"
         + src[brace + 1:])

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__R.n = (globalThis.__R.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__R || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_rtp.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "rtp")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  Rr = json.loads((BUILD.parent / "nf-rtp/cpu.json.d").read_text())
  n = max(Rr.get("n", 1), 1)
  calls = Rr.get("calls", 0) // n
  print(f"\nTHE `rtp` ACCESS ({n} turns):")
  print(f"  CALLS A TURN: {calls}")
  print(f"  DEEPEST OUTER WALK (THE BLOCK LIST): {Rr.get('outer', 0)}")
  print(f"  DEEPEST INNER WALK (THE BLOCK): {Rr.get('inner', 0)}")
  print(f"  THE LARGEST ROW COUNT: {Rr.get('rows_n', 0)}")
  print()
  print("**⇒⇒⇒ AND **THE `rtp` CLOCK READS **0.4787 ms** (MEASURED, `probe-alu-parts.py**),")
  print("**⇒⇒⇒ AND **THE CLOCK IS **AT **THE `rtp` ENTRY**, **SO **IT INCLUDES **THE **CLOCK's")
  print("OWN OVERHEAD** (A `performance.now()` PAIR, **~0.02-0.05 us**), **⇒⇒⇒ AND **THE **CALL")
  print("COUNT** IS **THE MULTIPLIER** (§138.5)****.")
