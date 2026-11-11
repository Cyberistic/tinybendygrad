#!/usr/bin/env python3
"""COUNT **THE RENDER's HOT FUNCTION CALLS** A TURN, **IN THE DAEMON** -- AND PRICE THEM.

**WHY:** THE RENDER's PARTS ARE **NESTED** AND **THE PARTS' NAMES ARE **A TREE**, BUT **THE
COST IS **A SUM OVER **THE LEAVES**, AND **THE LEAVES ARE **THE FUNCTIONS THAT ARE CALLED
MOST**. **⇒⇒⇒ SO THE QUESTION IS **"WHICH FUNCTION IS CALLED MOST"**, AND **THAT IS **A
COUNT**, AND **A COUNT COSTS NOTHING AT RUNTIME** (A COUNTER, NOT A CLOCK -- §138.3).

**AND THE COUNT IS **A COUNT OF **THE COMPILED FORM's CALL SITES** PLUS **THE RUNTIME
COUNT** -- AND **THE RUNTIME COUNT IS **THE ONE THAT MATTERS**, BECAUSE **A FUNCTION CALLED
FROM **TEN** PLACES RUNS **TEN** TIMES A TURN**.

**⇒⇒⇒ AND EVERY SITE IS **COUNTED BEFORE IT IS PATCHED**, SO A MISS IS **AN ERROR** AND NOT
**A SILENT ZERO** (THE TREE's OWN RULE).**
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

# **THE FUNCTIONS TO COUNT**, AND **WHY EACH IS HERE.** **THE LIST IS **THE COMPILED FORM's
# OWN NAMES**, SO **A RENAME OF **THE BEND DEF** BREAKS **THE COUNT** AND **SAYS SO** (THE
# PATCH COUNT IS 1, NOT 0).
SITES = [
  ("text_go", "$_________tinybendygrad_renderer_cstyle_ku_text_go"),
  ("pfx_ix", "$_________tinybendygrad_renderer_cstyle_ku_pfx_ix"),
  ("pfx", "$_________tinybendygrad_renderer_cstyle_ku_pfx"),
  ("st_put", "$_________tinybendygrad_renderer_cstyle_st_put"),
  ("St_r", "$_________tinybendygrad_renderer_cstyle_St_r"),
  ("KU_op", "$_________tinybendygrad_renderer_cstyle_KU_op"),
  ("String_concat", "$String_concat"),
  ("List_append", "$List_append"),
]


def instrument(src: str) -> str:
  for key, name in SITES:
    # **AND THE SITE IS **THE FUNCTION's **OPENING BRACE**, NOT **ITS NAME** -- BECAUSE
    # **INSERTING AFTER `function name(` LANDS **INSIDE THE PARAMETER LIST** (MEASURED: THE
    # PATCHED SOURCE READ `function $List_append(_xs_0, _ys_0) {` WITH THE COUNTER **BETWEEN
    # `(` AND `_xs_0`**, AND IT DID NOT PARSE).
    site = f"function {name}("
    n = src.count(site)
    if n != 1:
      raise SystemExit(f"WARN: the {key} site is {n} (want 1)")
    # **THE BRACE, FOUND BY COUNTING THE PARENS** (THE PARAMETER LIST MAY SPAN LINES).
    op = src.index("(", src.index(site))
    depth = 0
    cp = op
    for c in range(op, len(src)):
      if src[c] == "(":
        depth += 1
      elif src[c] == ")":
        depth -= 1
        if depth == 0:
          cp = c
          break
    brace = src.index("{", cp)
    src = (src[:brace + 1] + f"\n  globalThis.__C.{key} = (globalThis.__C.{key} || 0) + 1;"
           + src[brace + 1:])

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


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_hotcount.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "hotcount")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  C = json.loads((BUILD.parent / "nf-hotcount/cpu.json.d").read_text())
  n = max(C.get("n", 1), 1)
  print(f"\nTHE RENDER's HOT FUNCTION CALLS A TURN ({n} turns):")
  for key, _ in SITES:
    c = C.get(key, 0) // n
    print(f"  {key:16s} {c:8d}")
  print()
  print("**⇒⇒⇒ AND **THE TOP LIST** IS **THE CANDIDATE LIST** -- AND **§138's LESSON IS")
  print("**THE COUNT IS NOT THE COST** (THE `arg_of` CHAIN WAS **17 TESTS** AND COST **0.9%**")
  print("OF ITS PHASE), **SO **A COUNT IS **WHERE TO LOOK**, NOT **WHAT TO CHANGE**.**")
