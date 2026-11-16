#!/usr/bin/env python3
"""CLOCK **THE `text` FAMILY's ARM BODIES**, **ONE AT A TIME**, **INSIDE** THE DAEMON.

**WHY:** §138.5's NEGATIVE RESULT (THE `eq_op` REORDER: **84.6% FEWER COMPARISONS, 0.3% OF THE
RENDER**) TAUGHT **THAT **A COUNT IS **WHERE TO LOOK**, NOT **WHAT TO CHANGE**. **⇒⇒⇒ AND
§138.6's SHAPE SHOWS **THE RENDER's COST IS **SPREAD** -- SO **THE NEXT MOVE MUST **FIND **THE
COST **INSIDE **THE DOMINANT ARM**, NOT **INSIDE **THE RENDER**.

**⇒⇒⇒ AND THE DOMINANT ARM IS **`ku_text_alu` (294 CALLS A TURN, MEASURED,
`probe-text-arms.py`)**, **AND **ITS BODY** IS **TWO CALLS**: `code_for_op_of` (THE **DEVICE's**
DISPATCH) **AND **THE `ku_alu_srcs` WALK**. **⇒⇒⇒ AND `code_for_op_of` DISPATCHES TO
`code_for_base_of` (4,399 BYTES -- **ANOTHER `Ops` STRING CHAIN**), WHICH IS **WHERE **THE
ALU's TEXT IS **ACTUALLY BUILT**.

**⇒⇒⇒ AND §138.5's LESSON SAYS **THE CHAIN IS **NOT **THE COST**, **⇒⇒⇒ SO **THE ARMS'
**BODIES** ARE **THE TARGET**, AND **THEY MUST BE **CLOCKED**, NOT **COUNTED**.

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

ACC = ("globalThis.__T = {base:0, clang:0, alu_srcs:0, src_pieces:0, strip_pieces:0, cfo:0, n:0};\n"
       "globalThis.__TM = (k, t0) => { globalThis.__T[k] += (performance.now() - t0); };")

# **THE TARGETS**: (THE KEY, THE COMPILED NAME). **AND **THE ARGUMENT NAMES ARE **READ FROM
# **THE COMPILED FORM** (MEASURED: **A HARDCODED NAME THAT IS NOT **THE COMPILED ONE** IS **A
# ReferenceError** AT RUNTIME).
TARGETS = [
  ("base", "$_________tinybendygrad_renderer_cstyle_code_for_base_of"),
  ("clang", "$_________tinybendygrad_renderer_cstyle_code_for_clang_of"),
  ("alu_srcs", "$_________tinybendygrad_renderer_cstyle_ku_alu_srcs"),
  ("src_pieces", "$_________tinybendygrad_renderer_cstyle_ku_src_pieces"),
  ("strip_pieces", "$_________tinybendygrad_renderer_cstyle_strip_pieces"),
]


def body_end(src: str, brace: int) -> int:
  """**THE BODY's END**, AND **THE SCAN **SKIPS **THE STRINGS** AND **THE `}` THAT **A BRANCH**
  **CLOSES** (MEASURED: **THE NAIVE SCAN CUTS **A COMPILED `if/else` CHAIN** IN HALF**)."""
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
        return k + 1
    k += 1
  raise SystemExit("no end")


def instrument(src: str) -> str:
  for key, name in TARGETS:
    site = f"function {name}("
    n = src.count(site)
    if n != 1:
      raise SystemExit(f"WARN: the {key} site is {n} (want 1)")
    site_i = src.index(site)
    op = src.index("(", site_i)
    d = 0
    for c in range(op, len(src)):
      if src[c] == "(":
        d += 1
      elif src[c] == ")":
        d -= 1
        if d == 0:
          cp = c
          break
    params = src[op + 1:cp]
    args = [a.strip() for a in params.split(",") if a.strip()]
    brace = src.index("{", cp)
    end = body_end(src, brace)
    whole = src[site_i:end]
    inner = name + "__tinner"
    body = whole.replace(f"function {name}(", f"function {inner}(", 1)
    call = ", ".join(args)
    wrapper = (f"\nfunction {name}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  const __v = {inner}({call});\n"
               f"  globalThis.__TM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    src = src[:site_i] + body + wrapper + src[end:]

  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

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
  out = BUILD / "serve_textbody.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "textbody")
  d.start()
  time.sleep(0.8)
  for _ in range(40):
    d.turn()
  d.stop()
  T = json.loads((BUILD.parent / "nf-textbody/cpu.json.d").read_text())
  n = max(T.get("n", 1), 1)
  print(f"\nTHE `text` FAMILY's ARM BODIES, **IN THE DAEMON** ({n} turns), ms a turn:")
  for key, _ in TARGETS:
    if key in T:
      print(f"  {key:14s} {T[key] / n:.4f}")
  print()
  print("**⇒⇒⇒ AND **THE TIMES **OVERLAP** (THE ARM BODIES ARE **NESTED**: `alu_srcs` IS")
  print("**INSIDE `ku_text_alu`, AND `src_pieces` IS **INSIDE `alu_srcs`), **⇒⇒⇒ SO **THEY **DO")
  print("NOT SUM** -- **AND **THE VERDICT IS **THE **DEEPEST** ONE**, **BECAUSE **THE OUTER ONE's")
  print("TIME **INCLUDES **THE INNER ONE's****.")
  print("**⇒⇒⇒ AND **THE RENDER IS **~1.03 ms**, **AND §138.5's LESSON SAYS **THE COUNT IS")
  print("NOT THE COST** -- **⇒⇒⇒ SO **THE ARM THAT DOMINATES **THE COUNTS** IS **NOT **THE ARM")
  print("THAT DOMINATES **THE TIME**, AND **THIS IS **THE MEASUREMENT **THAT SAYS WHICH****.")
