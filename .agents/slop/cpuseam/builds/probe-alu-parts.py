#!/usr/bin/env python3
"""SPLIT **THE ALU's SOURCE WALK** INTO **ITS PARTS**, **IN THE DAEMON**.

**WHY:** MEASURED: **`ku_alu_srcs` IS **0.4709 ms** A TURN** (`probe-text-body.py`) -- **THE
LARGEST SINGLE ARM BODY MEASURED** -- **⇒⇒⇒ AND **ITS BODY HAS **FOUR** PIECES**:
  1. `rtp(r, h)` -- **A **TWO-LEVEL INDEXED** ACCESS** (`Rows_get` -> `Rows_blk`/`Rows_off`).
  2. `ku_op_at(kus, h)` -- **A **TWO-LEVEL INDEXED** ACCESS** (`ku_at` -> `List.get` TWICE).
  3. `eq_op(...)` -- **THE 75-ARM CHAIN** (PRICED, AND **§138.5 MEASURED **THAT **THE REORDER
     DOES NOT PAY**).
  4. `ku_src_pieces(...)` -> `strip_pieces` -> `drop_last` -- **THE STRIP**.

**⇒⇒⇒ AND §138.5's LESSON IS **THE COUNT IS NOT THE COST**, **⇒⇒⇒ SO **EACH PIECE MUST BE
**CLOCKED**, AND **THE CLOCKS ARE **INSIDE** THE FUNCTION BODIES**.

**⇒⇒⇒ AND `rtp` AND `ku_op_at` ARE **CALLED FROM **MANY PLACES** (THE INDEXES ARE **SHARED**),
**⇒⇒⇒ SO **THEIR CLOCKS **ARE **THE TOTAL**, AND **THE ALU's SHARE IS **WHAT **THE **ALU's OWN
CALLS** COST** -- **⇒⇒⇒ AND **THE **ALU-SPECIFIC** PIECES** (`eq_op` AND `ku_src_pieces`) **ARE
**COUNTED **AND **TIMED **INSIDE **THE ALU's LOOP**, WHERE **THEY ARE **THE ALU's OWN****.
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

ACC = ("globalThis.__A = {rtp:0, op_at:0, eq_op:0, src_pieces:0, n:0};\n"
       "globalThis.__AM = (k, t0) => { globalThis.__A[k] += (performance.now() - t0); };")


def body_end(src: str, brace: int) -> int:
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


def wrap(src: str, key: str, name: str) -> str:
  """**A CLOCK AT **THE FUNCTION's ENTRY**, AND **THE CLOCK IS **INSIDE** THE FUNCTION** -- **⇒⇒⇒
  AND **THE FUNCTION's OWN BODY IS **KEPT** (RENAMED), **AND **THE WRAPPER CALLS **IT****."""
  site = f"function {name}("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the {key} site is {src.count(site)}")
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
  inner = name + "__ainner"
  body = whole.replace(f"function {name}(", f"function {inner}(", 1)
  call = ", ".join(args)
  wrapper = (f"\nfunction {name}({params}) {{\n"
             f"  const __t = performance.now();\n"
             f"  const __v = {inner}({call});\n"
             f"  globalThis.__AM(\"{key}\", __t);\n"
             f"  return __v;\n"
             f"}}")
  return src[:site_i] + body + wrapper + src[end:]


def instrument(src: str) -> str:
  # **THE TWO INDEXED ACCESSES** -- **AND **THEY ARE **CALLED FROM **MANY PLACES****.
  src = wrap(src, "rtp", "$_________tinybendygrad_renderer_cstyle_rtp")
  src = wrap(src, "op_at", "$_________tinybendygrad_renderer_cstyle_ku_op_at")
  # **THE TWO ALU-SPECIFIC PIECES** -- **AND **THEY ARE **CALLED FROM **THE ALU's LOOP** (AND
  # **FROM **NOWHERE ELSE**, FOR `eq_op`)**.
  src = wrap(src, "eq_op", "$_________tinybendygrad_renderer_cstyle_eq_op")
  src = wrap(src, "src_pieces", "$_________tinybendygrad_renderer_cstyle_ku_src_pieces")

  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__A.n = (globalThis.__A.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__A || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_aluparts.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "aluparts")
  d.start()
  time.sleep(0.8)
  for _ in range(40):
    d.turn()
  d.stop()
  A = json.loads((BUILD.parent / "nf-aluparts/cpu.json.d").read_text())
  n = max(A.get("n", 1), 1)
  print(f"\nTHE ALU's SOURCE WALK, SPLIT INTO **ITS PARTS** ({n} turns), ms a turn:")
  for key in ("rtp", "op_at", "eq_op", "src_pieces"):
    if key in A:
      print(f"  {key:12s} {A[key] / n:.4f}")
  print()
  print("**⇒⇒⇒ AND `ku_alu_srcs` READS **0.4709 ms** (MEASURED, `probe-text-body.py`), **⇒⇒⇒")
  print("AND **THE FOUR PARTS ABOVE ARE **THE ALU's WORK**, **⇒⇒⇒ AND `rtp` AND `op_at` ARE")
  print("**CALLED FROM **MANY PLACES**, **⇒⇒⇒ SO **THEIR TIMES ARE **THE TOTALS** AND **THEY ARE")
  print("**THE **ALU's SHARE** ONLY IN PART****.")
