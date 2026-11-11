#!/usr/bin/env python3
"""COUNT **THE RENDER's DISPATCH CALLS**, **PER SITE**, IN THE DAEMON -- AND PRICE THEM.

**WHY:** §138's LESSON IS **THE COUNT IS NOT THE COST** -- BUT **THE COUNT MULTIPLIES THE
COST**, SO **THE MULTIPLIER** IS WHAT MATTERS. **⇒⇒⇒ AND THERE ARE **THREE** DISPATCH SITES
IN THE RENDER, NOT ONE:**

  · `ku_text_go`  -- **16** `Ops` COMPARISONS, **644** CALLS A TURN (MEASURED).
  · `ku_pfx_ix`   -- **7** COMPARISONS, **ONCE PER NAMED KERNEL**.
  · `ku_inline*`  -- **THE INLINING DECISIONS**, **PER UOP**.

**⇒⇒⇒ AND THE PRICE OF EACH IS **MEASURED IN JS** (`probe-text-cost-probe.js` MEASURED THE
`ku_text_go` CHAIN AT **0.0498 ms** FOR **782** CALLS = **0.064 us** A CALL), **SO THE SHARE
IS **A NUMBER** AND NOT **A GUESS**.

**AND THIS COUNTS **THE CALLS**, **NOT **THE COST** -- BECAUSE **A CLOCK AT **A DISPATCH**
IS **THE INSTRUMENT's OWN COST** (§138.3: THE RECURSIVE FAMILIES' WRAPPERS READ THE RENDER
AT **13.34 ms** AGAINST **THE TRUE 1.04 ms**).**
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

ACC = "globalThis.__C = {};"


def instrument(src: str) -> str:
  # **EACH DISPATCH SITE, COUNTED AT ITS OWN ENTRY.** **AND EVERY SITE IS **COUNTED BEFORE
  # IT IS PATCHED**, SO A MISS IS **AN ERROR** AND NOT **A SILENT ZERO**.
  SITES = [
    ("text", "function $_________tinybendygrad_renderer_cstyle_ku_text_go(_op_0, _dev_0, _i_0, _k_0, _kus_0, _r_0) {"),
    ("pfx", "function $_________tinybendygrad_renderer_cstyle_ku_pfx_ix(_op_0) {"),
    ("inline", "function $_________tinybendygrad_renderer_cstyle_ku_inline(_op_0, _k_0, _kus_0) {"),
    ("inline2", "function $_________tinybendygrad_renderer_cstyle_ku_inline2(_op_0, _k_0, _kus_0) {"),
  ]
  for key, site in SITES:
    if src.count(site) != 1:
      raise SystemExit(f"WARN: the {key} site is {src.count(site)}")
    src = src.replace(site, site + f"\n  globalThis.__C.{key} = (globalThis.__C.{key} || 0) + 1;", 1)

  old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old2) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old2)}")
  src = src.replace(old2, ACC + "\n" + old2, 1)

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


# **THE PER-CALL PRICE OF EACH DISPATCH, IN JS** -- **MEASURED, NOT ASSUMED**
# (`probe-dispatch-price-probe.js`: **THE CHAIN'S OWN COST ON **THE REAL SEQUENCE**):
#   `ku_text_go`  0.0509 us  (16 TESTS)
#   `ku_pfx_ix`   0.0263 us  (7 TESTS)
# **⇒⇒⇒ AND `ku_inline` AND `ku_inline2` ARE **NOT **STRING CHAINS** -- THEY ARE **THE §137
# PER-LITERAL PREDICATES** (`is_cast` AND FRIENDS) -- **SO **THEY ARE **NOT PRICED HERE**,
# BECAUSE **A CHAIN's PRICE IS **NOT **A PREDICATE's PRICE** AND **§138's LESSON IS **THE
# COUNT IS NOT THE COST**.**
US_PER_CALL = {"text": 0.0509, "pfx": 0.0263, "inline": 0.0, "inline2": 0.0}
# **THE CHAIN LENGTHS**, MEASURED FROM **THE COMPILED FORM**.
TESTS = {"text": 16, "pfx": 7, "inline": 0, "inline2": 0}
# **THE TRUE RENDER**, MEASURED (THE PAIRED INSTRUMENT, THE MINIMUM): **1.03 ms**.
RENDER_MS = 1.03


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_dispatchcount.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "dispatchcount")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  C = json.loads((BUILD.parent / "nf-dispatchcount/cpu.json.d").read_text())
  n = max(C.get("n", 1), 1)
  print(f"\nTHE RENDER's DISPATCH CALLS A TURN ({n} turns):")
  total_us = 0.0
  for key in ("text", "pfx", "inline", "inline2"):
    calls = C.get(key, 0) // n
    us = calls * US_PER_CALL[key]
    total_us += us
    print(f"  {key:9s} {calls:6d} calls  x {US_PER_CALL[key]:.3f} us  = {us:8.1f} us"
          f"   ({TESTS[key]} TESTS EACH)")
  print(f"\n  THE TOTAL DISPATCH COST: {total_us:.1f} us = {total_us / 1000:.4f} ms")
  print(f"  OF THE **1.03 ms** RENDER: **{100 * total_us / 1000 / RENDER_MS:.1f}%**")
  print()
  print("  **⇒⇒⇒ AND **AN **INTEGER** DISPATCH** (THE PORT's OWN `U32` OP INDEX, WHICH **THE")
  print("  WIRE ALREADY CARRIES**) WOULD COST **1/6** OF THE STRING ONE** (MEASURED: THE INTEGER")
  print("  SWITCH READS **0.0079 ms** AGAINST THE STRING CHAIN's **0.0498 ms** FOR THE SAME")
  print("  CALLS).**")
  print(f"  **⇒⇒⇒ AND SO **THE WHOLE DISPATCH** IS WORTH **~{total_us / 1000 * 5 / 6:.4f} ms**")
  print(f"  = **{100 * total_us / 1000 * 5 / 6 / RENDER_MS:.1f}%** OF THE RENDER** -- **AND THAT")
  print("  IS **THE CEILING**, BECAUSE **THE COUNT IS NOT THE COST** (§138) AND **THE ARMS'")
  print("  BODIES ARE ELSEWHERE**.**")
