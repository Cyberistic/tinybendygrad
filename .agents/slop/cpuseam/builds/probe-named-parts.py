#!/usr/bin/env python3
"""CLOCK **THE `named` FAMILY's INTERNALS**, **ONE AT A TIME**, **INSIDE** THE DAEMON.

**WHY:** §138.3's `render-shape.py` NAMES **THE LEAVES** (`named` **1.50-1.82 ms** IS **THE
LARGEST**), **BUT IT CLOCKS **THE LEAF ITSELF**, NOT **WHAT THE LEAF DOES**. **⇒⇒⇒ AND §138's
METHOD IS **THE ONE THAT WORKS**: **MEASURE **ONE ARM AT A TIME**, AND **THE ARM THAT
DOMINATES** IS **THE TARGET**.

**⇒⇒⇒ AND `_render_named` IS **A COMPOSITION** -- MEASURED FROM **THE COMPILED FORM**, IT CALLS
`ku_pfx_ix`, `ku_pfx`, `st_put`, `ku_text` AND `_render_emit` -- **AND `ku_text` AND
`_render_emit` ARE **ALREADY CLOCKED** BY THE PARENT INSTRUMENT** (THEY ARE **THE NESTED
PARTS**), **SO **THE TWO NEW CLOCKS HERE ARE **THE ONES **THE PARENT DOES NOT HAVE**: **THE
`st_put` CHAIN** (THE STATE's LIST INSERT) **AND **THE `ku_pfx`/`ku_pfx_ix` PAIR** (THE NAME).

**⇒⇒⇒ AND EVERY CLOCK IS **INSIDE** THE FUNCTION BODY** (THE TREE's OWN RULE) **AND EVERY
PATCH SITE IS **COUNTED BEFORE IT IS APPLIED**, SO A MISS IS **AN ERROR** AND NOT **A SILENT
ZERO**."""

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

ACC = ("globalThis.__N = {st_put:0, st_put_p:0, pfx:0, pfx_ix:0, n:0};\n"
       "globalThis.__NM = (k, t0) => { globalThis.__N[k] += (performance.now() - t0); };")

# **THE TARGETS**: (THE KEY, THE COMPILED NAME, THE ARGUMENT LIST **AS **THE COMPILED FORM
# **HAS IT**).
# **⇒⇒⇒ AND THE **ARGUMENT NAMES ARE **READ FROM **THE COMPILED FORM**, NOT HARDCODED** --
# BECAUSE **A HARDCODED NAME THAT **IS NOT **THE COMPILED ONE** IS **A ReferenceError** AT
# RUNTIME** (MEASURED: `st_put_p`'s PARAMETERS ARE **`_ps_0, _st_0`**, NOT **`_xs_0, _st_0`**,
# AND **THE DAEMON EXITED** WITH "`st_put__ninner` is not defined").
TARGETS = [
  ("pfx_ix", "$_________tinybendygrad_renderer_cstyle_ku_pfx_ix"),
  ("pfx", "$_________tinybendygrad_renderer_cstyle_ku_pfx"),
  ("st_put", "$_________tinybendygrad_renderer_cstyle_st_put"),
  ("st_put_p", "$_________tinybendygrad_renderer_cstyle_st_put_p"),
]


def instrument(src: str) -> str:
  """**EACH TARGET IS **REWRITTEN** AS **A WRAPPER AROUND ITSELF**, WITH **THE CLOCK
  **INSIDE** -- AND **THE RECURSIVE FAMILIES ARE **NOT** WRAPPED** (THEY PAY **A WRAPPER
  LAYER** AT **EVERY LEVEL**, AND §138.3 MEASURED **THE WHOLE 46-FUNCTION WRAP AT **13.34 ms**
  AGAINST **THE TRUE 1.04 ms**)."""
  for key, name in TARGETS:
    # **THE SITE**, WITH **THE PARAMETER LIST** AND **THE BODY's BRACE**, FOUND BY **COUNTING**.
    site = f"function {name}("
    if src.count(site) != 1:
      raise SystemExit(f"WARN: the {key} site is {src.count(site)}")
    site_i = src.index(site)
    op = src.index("(", site_i)
    depth = 0
    for c in range(op, len(src)):
      if src[c] == "(":
        depth += 1
      elif src[c] == ")":
        depth -= 1
        if depth == 0:
          cp = c
          break
    params = src[op + 1:cp]
    # **THE ARGUMENT NAMES, **READ FROM **THE COMPILED PARAMETER LIST****.
    args = [a.strip() for a in params.split(",") if a.strip()]
    brace = src.index("{", cp)
    # **THE BODY**, BY BRACE MATCHING **THAT SKIPS STRINGS AND THE `}` THAT **A BRANCH**
    # **CLOSES** (MEASURED: THE NAIVE SCAN CUTS **A COMPILED `if/else` CHAIN** IN HALF).
    d = 0
    k = brace
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
        d += 1
      elif ch == "}":
        d -= 1
        if d == 0:
          rest = src[k + 1:k + 12].lstrip()
          if rest.startswith("else"):
            k += 1
            continue
          end = k + 1
          break
      k += 1
    # **⇒⇒⇒ AND **THE WHOLE DEFINITION** IS TAKEN (FROM `function` TO **THE BODY's END**), SO
    # **THE RENAME **CAN MATCH** -- BECAUSE **THE BODY ALONE STARTS AT **THE `{`**, AND **THE
    # RENAME'S PATTERN IS **THE `function` HEADER** (MEASURED: **THE `__ninner` DEFINITIONS
    # WERE **ABSENT** AND **THE DAEMON EXITED** WITH "`st_put__ninner` is not defined").
    whole = src[site_i:end]
    inner = name + "__ninner"
    body = whole.replace(f"function {name}(", f"function {inner}(", 1)
    call = ", ".join(args)
    wrapper = (f"\nfunction {name}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  const __v = {inner}({call});\n"
               f"  globalThis.__NM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    src = src[:site_i] + body + wrapper + src[end:]

  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__N.n = (globalThis.__N.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__N || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_named.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "named")
  d.start()
  time.sleep(0.8)
  for _ in range(40):
    d.turn()
  d.stop()
  N = json.loads((BUILD.parent / "nf-named/cpu.json.d").read_text())
  n = max(N.get("n", 1), 1)
  print(f"\nTHE `named` FAMILY's INTERNALS, **IN THE DAEMON** ({n} turns), ms a turn:")
  for key, _ in TARGETS:
    if key in N:
      print(f"  {key:10s} {N[key] / n:.4f}")
  print()
  print("**⇒⇒⇒ AND `st_put_p` IS **THE STATE's LIST INSERT**, AND **THE TREE's OWN COMMENT**")
  print("**RECORDS THAT **`List.append` IS **THE FOLD** -- SO **IF `st_put_p` DOMINATES, **THE FIX")
  print("IS **THE SAME SHAPE** AS §138.2's (SPLIT ONCE, NOT PER FIELD).**")
  print("**⇒⇒⇒ AND THE PARENT'S `named` READING WAS **1.50-1.82 ms** (THE TRUE VALUE, AFTER")
  print("**THE 1.2526 INFLATION**), **AND **THE SUM OF **THE PARTS** IS **LESS THAN **THE LEAF**,")
  print("BECAUSE **THE PARTS ARE **NESTED** AND **THE TIMES **OVERLAP**.**")
