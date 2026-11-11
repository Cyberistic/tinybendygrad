#!/usr/bin/env python3
"""COUNT **THE `ku_text_go` CALLS** A TURN, **IN THE DAEMON**.

**WHY:** THE DISPATCH'S SHARE OF THE RENDER DEPENDS ON **HOW MANY TIMES IT RUNS**, AND
**THE WIRE's ROW COUNT (782) IS **NOT** THE CALL COUNT** -- BECAUSE **THE RENDERER RE-TEXTS
A KERNEL'S UOPS **PER KERNEL**, AND THE WIRE CARRIES **FIVE** KERNELS. **⇒⇒⇒ SO THE CALL
COUNT MUST BE **COUNTED**, NOT INFERRED.**

**AND THE COUNT IS **COUNTED IN THE COMPILED FORM** (A COUNTER AT THE CALL SITE, PARENTHESIZED
-- **AN UNPARENTHESIZED COUNTER AT A CALL SITE BECOMES **AN EXTRA ARGUMENT** AND THE BUILD
HANGS**, THE TREE's OWN RULE) **AND READ AT THE `@@END`**.

**AND THE COUNT IS **A COUNT AND NOT A CLOCK**, BECAUSE **A CLOCK AT **THE DISPATCH** WOULD
BE **THE INSTRUMENT's OWN COST** (MEASURED, §138.3: WRAPPING THE RECURSIVE FAMILIES READS THE
RENDER AT **13.34 ms** AGAINST **THE TRUE 1.04 ms**). **⇒⇒⇒ AND §138's LESSON: **THE COUNT IS
NOT THE COST** -- BUT **THE COUNT MULTIPLIES THE COST**, SO IT IS **THE MULTIPLIER** THAT
MATTERS.**
"""

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

ACC = "globalThis.__C = {text:0};"


def instrument(src: str) -> str:
  # **THE COUNTER, AT **THE `ku_text_go` ENTRY**. **AND IT IS **A COUNTER**, NOT A CLOCK --
  # **AND IT IS **PARENTHESIZED** SO IT IS **NOT** AN EXTRA ARGUMENT** (THE TREE's OWN RULE).
  old = "function $_________tinybendygrad_renderer_cstyle_ku_text_go(_op_0, _dev_0, _i_0, _k_0, _kus_0, _r_0) {"
  new = ("function $_________tinybendygrad_renderer_cstyle_ku_text_go(_op_0, _dev_0, _i_0, _k_0, _kus_0, _r_0) {\n"
         "  globalThis.__C.text += 1;")
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the ku_text_go site is {src.count(old)}")
  src = src.replace(old, new, 1)

  # **THE ACCUMULATOR**, AT THE TOP OF `$serve`.
  old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old2) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old2)}")
  src = src.replace(old2, ACC + "\n" + old2, 1)

  # **THE DUMP**, AT THE `@@END`.
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__C.n = (globalThis.__C.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__C || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_textcount.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "textcount")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  C = json.loads((BUILD.parent / "nf-textcount/cpu.json.d").read_text())
  n = max(C.get("n", 1), 1)
  print(f"\nTHE `ku_text_go` CALLS A TURN: **{C.get('text', 0) // n}** (over {n} turns)")
  print("AND THE WIRE CARRIES **782** ROWS -- SO THE RENDERER RE-TEXTS **EACH KERNEL's**")
  print("UOPS **PER KERNEL**.")
  # **AND THE DISPATCH'S SHARE**, WITH **THE MEASURED PER-CALL COST**.
  per_call = 0.0498 / 782   # MEASURED, `probe-text-cost-probe.js`: 0.0498 ms FOR 782 CALLS.
  calls = C.get("text", 0) // n
  print(f"\n**⇒⇒⇒ AND THE DISPATCH'S SHARE OF THE RENDER:**")
  print(f"  THE CHAIN COSTS **{per_call * 1000:.3f} us** A CALL (MEASURED, "
        f"`probe-text-cost-probe.js`: 0.0498 ms FOR 782 CALLS).")
  print(f"  **{calls}** CALLS A TURN -> **{per_call * calls:.4f} ms** OF THE **1.03 ms** RENDER")
  print(f"  = **{100 * per_call * calls / 1.03:.1f}%** OF THE RENDER.")
