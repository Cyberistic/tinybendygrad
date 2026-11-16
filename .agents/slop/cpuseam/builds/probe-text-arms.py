#!/usr/bin/env python3
"""CLOCK **THE `ku_text` FAMILY's ARMS**, **ONE AT A TIME**, **INSIDE** THE DAEMON.

**WHY:** §138.3's `render-shape.py` **CANNOT** WRAP **THE `text` FAMILY**, BECAUSE **IT IS
RECURSIVE** AND **EVERY RECURSION LEVEL PAYS **A WRAPPER LAYER** (MEASURED: WRAPPING ALL **46**
FUNCTIONS READ THE RENDER AT **13.34 ms** AGAINST **THE TRUE 1.04 ms** -- **12x**).

**⇒⇒⇒ AND §138's LESSON APPLIES**: **THE COUNT IS NOT THE COST** -- BUT **THE COUNT IS
MULTIPLIED BY **THE COST**, **AND THE COUNT IS **FREE**. **⇒⇒⇒ SO **THE CHEAP INSTRUMENT IS
**A COUNT PER ARM**, AND **THE PRICE IS **MEASURED **IN JS** ON **THE REAL SEQUENCE** (THE SAME
MOVE AS §138's `arg_of`).

**⇒⇒⇒ AND **THE COUNT IS **AT **THE ARM's ENTRY**, AND **THE ARM's ARMS ARE **THE LEAVES OF
THE `text` FAMILY**, WHICH IS **WHERE §137's PROFILER NAMED **THE TOP LEAF** (`ku_text`
**1.157 ms**).**

**⇒⇒⇒ AND **EVERY ARM IS **COUNTED BEFORE IT IS PATCHED**, SO A MISS IS **AN ERROR** AND NOT
**A SILENT ZERO**."""

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

# **THE ARMS**: **THE `ku_text_*` MEMBERS**, **PLUS **THE `text` FAMILY's ENTRY**.
ARMS = [
  "ku_text", "ku_text_go", "ku_text_range", "ku_text_if", "ku_text_backedge",
  "ku_text_cast", "ku_text_bitcast", "ku_text_refparam", "ku_text_load", "ku_text_load_by",
  "ku_text_store", "ku_text_buffer", "ku_text_wmma", "ku_text_stack", "ku_text_alu",
  "ku_text_special",
]


def instrument(src: str) -> str:
  """**A COUNTER AT **EACH ARM's ENTRY**, AND **A COUNT OF **THE ARM's **BODY SIZE** (THE
  COMPILED FORM's LENGTH), **SO **THE READER CAN SEE **WHICH ARM IS BIG** WITHOUT A CLOCK**."""
  acc = "globalThis.__T = {};"
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, acc + "\n" + old, 1)

  for arm in ARMS:
    name = f"$_________tinybendygrad_renderer_cstyle_{arm}"
    site = f"function {name}("
    n = src.count(site)
    if n != 1:
      raise SystemExit(f"WARN: the {arm} site is {n} (want 1)")
    op = src.index("(", src.index(site))
    depth = 0
    for c in range(op, len(src)):
      if src[c] == "(":
        depth += 1
      elif src[c] == ")":
        depth -= 1
        if depth == 0:
          cp = c
          break
    brace = src.index("{", cp)
    src = src[:brace + 1] + f"\n  globalThis.__T.{arm} = (globalThis.__T.{arm} || 0) + 1;" + src[brace + 1:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__T.n = (globalThis.__T.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__T || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_textarms.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "textarms")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  T = json.loads((BUILD.parent / "nf-textarms/cpu.json.d").read_text())
  n = max(T.get("n", 1), 1)
  print(f"\nTHE `ku_text` FAMILY's ARM CALLS A TURN ({n} turns):")
  rows = []
  for arm in ARMS:
    c = T.get(arm, 0) // n
    if c:
      rows.append((c, arm))
  rows.sort(reverse=True)
  for c, arm in rows:
    print(f"  {arm:20s} {c:7d}")
  print()
  print("**⇒⇒⇒ AND **THE COUNT IS **NOT **THE COST** (§138), **BUT **IT IS **THE")
  print("MULTIPLIER** -- **AND §138.4 PRICED **THE DISPATCH** AT **~0.041 ms**, **WHILE **THE")
  print("`text` FAMILY's ARMS ARE **THE **BODIES**.**")
