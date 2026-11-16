#!/usr/bin/env python3
"""COUNT **THE `eq_op` CHAIN's CALLS** AND **THE `ku_alu_srcs_go` ACCUMULATOR's LENGTH**.

**WHY:** MEASURED FROM **THE COMPILED FORM**: **`eq_op` IS **A 151-ARM CHAIN** (9,914 BYTES)
WITH **TWO** CALL SITES, AND **ONE** OF THEM IS **THE VARIABLE-vs-VARIABLE COMPARISON** THAT
§137 KEPT (`eq_op(ku_op_at(kus, h), op)`) -- **AND **§137's FINDING WAS **THAT **THE CHAIN'S
TEST COUNT IS **NOT **THE COST** (THE `arg_of` CHAIN WAS **17 TESTS** AND COST **0.9%** OF ITS
PHASE).

**⇒⇒⇒ AND `ku_alu_srcs_go` USES **THE O(n) FORM** OF `List.append`
(`List.append(_acc_0, {...})`), **WHICH COPIES **THE ACCUMULATOR** -- **AND §138.2's FIX WAS
**EXACTLY THIS SHAPE** (SPLIT ONCE, NOT PER FIELD), **AND §138.4's `probe-list-sites.py`
FOUND **THE HARNESS's OWN COPY** OF IT.**

**⇒⇒⇒ SO **BOTH** ARE COUNTED HERE: **THE `eq_op` CALL COUNT** (A COUNTER, NOT A CLOCK) **AND
**THE ACCUMULATOR's LENGTH** (A WALK, WHICH IS **THE FOLD's OWN COST**)."""

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


def instrument(src: str) -> str:
  acc = "globalThis.__E = {eq_op:0, alu_acc:0, alu_n:0, op_at:0, n:0};"
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, acc + "\n" + old, 1)

  # **THE `eq_op` COUNTER**, AT ITS ENTRY.
  site = "function $_________tinybendygrad_renderer_cstyle_eq_op("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the eq_op site is {src.count(site)}")
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
  src = src[:brace + 1] + "\n  globalThis.__E.eq_op = (globalThis.__E.eq_op || 0) + 1;" + src[brace + 1:]

  # **THE `ku_alu_srcs_go` ACCUMULATOR's LENGTH** -- **AND IT IS **MEASURED **AT THE POINT
  # **THE ACCUMULATOR IS **BUILT**, WHICH IS **WHERE **THE FOLD's COST IS**."
  site2 = "function $_________tinybendygrad_renderer_cstyle_ku_alu_srcs_go("
  if src.count(site2) != 1:
    raise SystemExit(f"WARN: the ku_alu_srcs_go site is {src.count(site2)}")
  # **THE ACCUMULATOR IS **THE SIXTH PARAMETER** (`$5`), AND **THE FOLD'S RESULT** IS **THE
  # `List.append(_acc_0, ...)`** -- **SO **THE LENGTH IS **COUNTED **AT **THE `List.append`
  # CALL**, WHERE **`_acc_0` IS **IN SCOPE**."""
  m = re.search(r'\$\$List_append\(_acc_0, ', src)
  if not m:
    raise SystemExit("WARN: no List_append(_acc_0, ...) in the build")
  pos = m.start()
  # **⇒⇒⇒ AND THE **COMMA EXPRESSION** IS **PARENTHESIZED** -- BECAUSE **THE CALL IS **AN
  # ARGUMENT** OF **ANOTHER CALL** AND **A BARE COMMA EXPRESSION** IN **AN ARGUMENT POSITION**
  # READS AS **TWO ARGUMENTS** (MEASURED: "Expected `)` but found `;`").
  walk = ('((function() { let __l = 0, __x = _acc_0; while (__x && __x.$ === "Con") '
          '{ __l += 1; __x = __x.tail; } '
          'globalThis.__E.alu_acc = Math.max(globalThis.__E.alu_acc || 0, __l); '
          'globalThis.__E.alu_n = (globalThis.__E.alu_n || 0) + 1; return 0; })())')
  # **⇒⇒⇒ AND **THE CALL's CLOSING PAREN** IS **FOUND FIRST** (BY COUNTING), **BECAUSE **THE
  # WALK's OWN PARENS MUST NOT BE COUNTED** -- **AND **THE OUTER PAREN IS **CLOSED **RIGHT
  # AFTER **THE CALL****.
  op2 = src.index("(", pos)
  d2 = 0
  for x in range(op2, len(src)):
    if src[x] in "([{":
      d2 += 1
    elif src[x] in ")]}":
      d2 -= 1
      if d2 == 0:
        cp2 = x
        break
  src = src[:pos] + "(" + walk + ", " + src[pos:cp2 + 1] + ")" + src[cp2 + 1:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__E.n = (globalThis.__E.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__E || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_eqop.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "eqop")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  E = json.loads((BUILD.parent / "nf-eqop/cpu.json.d").read_text())
  n = max(E.get("n", 1), 1)
  print(f"\nTHE `eq_op` CHAIN AND **THE ALU's ACCUMULATOR** ({n} turns):")
  print(f"  eq_op CALLS A TURN: {E.get('eq_op', 0) // n}")
  print(f"  THE ALU's ACCUMULATOR: {E.get('alu_n', 0) // n} BUILDS, DEEPEST {E.get('alu_acc', 0)} ELEMENTS")
  print()
  print("**⇒⇒⇒ AND `eq_op` IS **A 151-ARM CHAIN** (9,914 BYTES) -- **SO **ITS PRICE IS")
  print("**NOT** ~0.064 us** LIKE **THE 16-ARM `ku_text_go` CHAIN**; **IT IS ~9x LONGER** --")
  print("**⇒⇒⇒ AND **THE COUNT IS **THE MULTIPLIER** (§138).**")
  print("**⇒⇒⇒ AND **THE ALU's ACCUMULATOR** IS **THE O(n) FORM**, **AND §138.2's FIX WAS")
  print("**EXACTLY THIS SHAPE** -- **SPLIT ONCE, NOT PER FIELD** -- **AND §138.4's")
  print("`probe-list-sites.py` FOUND **THE HARNESS's OWN COPY** OF **THE SAME SHAPE**.**")
