#!/usr/bin/env python3
"""COUNT **THE INDEXED ACCESS's DEPTH** -- `Rows_get`'s AND `ku_at`'s -- **IN THE DAEMON**.

**WHY:** §138.7's MEASUREMENT PUT **THE ALU's SOURCE WALK** (`ku_alu_srcs`) AT **0.4709 ms**,
**THE LARGEST SINGLE ARM BODY** MEASURED -- **⇒⇒⇒ AND ITS BODY HAS **TWO INDEXED ACCESSES**:
`rtp(r, h)` -> `Rows_get(r, n-1-h)` -> `List.get(rows, index)`, **AND** `ku_op_at(kus, h)` ->
`ku_at(kus, h)` -> **ANOTHER INDEXED WALK**. **⇒⇒⇒ AND `List.get` IS **O(index)** (THE
PRELUDE: `case h <> t 1n+p: List.get(a, A, t, p)`), **⇒⇒⇒ SO **THE INDEX's DEPTH IS **THE
COST**, AND **IT MUST BE **COUNTED**, NOT GUESSED.**

**⇒⇒⇒ AND **THE COUNT IS **A WALK**, WHICH IS **WHAT `List.get` DOES ANYWAY** -- **⇒⇒⇒ SO
**THE INSTRUMENT'S COST IS **THE COST IT MEASURES**, **AND **THE DEPTHS ARE **READABLE FROM
**THE INSTRUMENT's OWN OUTPUT** (THE INSTRUMENT COUNTS **THE ELEMENTS **IT WALKS**)****.

**⇒⇒⇒ AND EVERY PATCH SITE IS **COUNTED BEFORE IT IS APPLIED**, SO A MISS IS **AN ERROR** AND
NOT **A SILENT ZERO** (THE TREE's OWN RULE)."""

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

ACC = "globalThis.__I = {rows_get:0, rows_n:0, ku_at:0, ku_n:0, n:0};"


def walk(name: str, var: str, key: str, cnt: str):
  """**THE WALK**, INLINED **AT **THE CALL**, AS **AN EXPRESSION** -- **AND **THE OUTER PAREN
  MATTERS** (MEASURED: **A BARE COMMA EXPRESSION **IN **AN ARGUMENT POSITION** READS AS **TWO
  ARGUMENTS**)."""
  return (f"((function() {{ let __l = 0, __x = {var}; while (__x && __x.$ === \"Con\") "
          f"{{ __l += 1; __x = __x.tail; }} "
          f"globalThis.__I.{key} = Math.max(globalThis.__I.{key} || 0, __l); "
          f"globalThis.__I.{cnt} = (globalThis.__I.{cnt} || 0) + 1; return 0; }}())")


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  # **THE `Rows_get` SITE**: **THE INDEXED WALK** IS **INSIDE `List.get`**, SO **THE DEPTH OF
  # **THE BLOCK** IS **COUNTED** (THE BLOCK IS **THE LIST `List.get` WALKS**).
  m = re.search(r'\$\$List_get\(\$?_b_0, \(_x_0 \)\)', src)
  if not m:
    raise SystemExit("WARN: no List.get(_b_0, ...) in the build")
  # **AND **THE `List.get`'s OWN WALK** IS **THE DEPTH** -- SO **THE INSTRUMENT COUNTS **THE
  # ARGUMENT's LENGTH** AND **THE LIST's LENGTH** BOTH.
  site = "function $_________tinybendygrad_renderer_cstyle_Rows_get("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the Rows_get site is {src.count(site)}")
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
  # **THE BLOCK'S LENGTH** IS **COUNTED AT **THE `Rows_get` ENTRY**, WHERE `_r_0` AND `_d_0` ARE
  # IN SCOPE -- **AND **THE BLOCK IS **`Rows_blk(r, bi)`**, WHICH IS **THE LIST `List.get` WALKS**.
  src = (src[:brace + 1]
         + "\n  { let __l = 0, __x = $$_________tinybendygrad_renderer_cstyle_Rows_blk(_r_0, "
           "$$_________tinybendygrad_renderer_cstyle_Rows_bi(_r_0, _d_0)); "
           "while (__x && __x.$ === \"Con\") { __l += 1; __x = __x.tail; } "
           "globalThis.__I.rows_get = Math.max(globalThis.__I.rows_get || 0, __l); "
           "globalThis.__I.rows_n = (globalThis.__I.rows_n || 0) + 1; }"
         + src[brace + 1:])

  # **⇒⇒⇒ AND **THE PARAMETER NAME** IS **READ FROM **THE COMPILED FORM**, **NOT GUESSED** --
  # BECAUSE **A WRONG NAME IS **A ReferenceError** AT RUNTIME** (MEASURED: **`_ks_0` IS NOT
  # **A PARAMETER** -- IT IS **`_kus_0`** -- **AND **THE DAEMON EXITED**).
  # **THE `ku_at` SITE**: **THE KERNEL's LIST**.
  site2 = "function $_________tinybendygrad_renderer_cstyle_ku_at("
  if src.count(site2) != 1:
    raise SystemExit(f"WARN: the ku_at site is {src.count(site2)}")
  op2 = src.index("(", src.index(site2))
  d2 = 0
  for c in range(op2, len(src)):
    if src[c] == "(":
      d2 += 1
    elif src[c] == ")":
      d2 -= 1
      if d2 == 0:
        cp2 = c
        break
  brace2 = src.index("{", cp2)
  src = (src[:brace2 + 1]
         + "\n  { let __l = 0, __x = _kus_0; while (__x && __x.$ === \"Con\") { __l += 1; __x = __x.tail; } "
           "globalThis.__I.ku_at = Math.max(globalThis.__I.ku_at || 0, __l); "
           "globalThis.__I.ku_n = (globalThis.__I.ku_n || 0) + 1; }"
         + src[brace2 + 1:])

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__I.n = (globalThis.__I.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__I || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_index.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "index")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  I = json.loads((BUILD.parent / "nf-index/cpu.json.d").read_text())
  n = max(I.get("n", 1), 1)
  print(f"\nTHE INDEXED ACCESSes' DEPTHS ({n} turns):")
  print(f"  Rows_get CALLS: {I.get('rows_n', 0) // n}   DEEPEST BLOCK: {I.get('rows_get', 0)}")
  print(f"  ku_at    CALLS: {I.get('ku_n', 0) // n}   DEEPEST KERNEL LIST: {I.get('ku_at', 0)}")
  print()
  print("**⇒⇒⇒ AND **THE ELEMENT COUNT IS **THE WALK's LENGTH**, **AND **THE WALK IS **WHAT")
  print("`List.get` DOES ANYWAY** -- **⇒⇒⇒ SO **THE DEPTH IS **THE COST** AND **THE DEPTHS ARE")
  print("**THE NUMBERS TO BEAT****.")
