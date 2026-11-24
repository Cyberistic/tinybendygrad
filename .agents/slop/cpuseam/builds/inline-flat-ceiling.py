#!/usr/bin/env python3
"""**THE **CEILING **OF **FLATTENING **THE **`ku_inline` **CHAIN**, **MEASURED **IN **THE **DAEMON** --
**⇒⇒† AND **AND **THE **CHAIN **IS **NINE **NESTED **CALLS **FOR **ONE **BOOLEAN**.

**WHY.** `inline-family-shape.py` **READS**: **`ku_inline` **IS **0.571 ms **A **TURN **OVER **644
**CALLS** -- **⇒⇒† AND **AND **IT **IS **NINE **FUNCTIONS **DEEP** (⇒⇒† AND **`ku_inline` → `ku_inline2`
**→ **`ku_inline2b`** → **`ku_inline2b2`** → ...)** -- **⇒⇒† AND **AND **THE **EXCLUSIVE **TIME **OF
**EACH **LEVEL **IS **SMALL** (⇒⇒† AND **`ku_inline` **MINUS **`ku_inline2` **IS **0.051 ms**)**.

**⇒⇒† AND **SO **THE **QUESTION **IS **WHETHER **THE **CHAIN's **CALL **OVERHEAD **IS **THE **COST** --
**⇒⇒† AND **AND **THE **CEILING **IS **MEASURED **BY **INLINING **THE **CHAIN **IN **THE **COMPILED
**FORM** (⇒⇒† AND **AND **THE **OUTPUT **IS **UNCHANGED**, **⇒⇒† AND **AND **SO **THIS **IS **A **REAL
**FIX **AND **NOT **A **BREAKING **ONE**)**
"""

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

WALL_OLD = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
WALL_NEW = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
DUMP_OLD = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
DUMP_NEW = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".w",
        JSON.stringify({W: globalThis.__W || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""


def find_fn(src: str, name: str):
  i = src.find(f"function {name}(")
  if i < 0:
    return None, None
  j = src.index("{", i)
  depth = 0
  k = j
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
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        return i, k + 1
    k += 1
  return i, None


def patch(src: str) -> str:
  """**THE **CHAIN **IS **REPLACED **BY **ONE **FUNCTION **THAT **CALLS **THE **LEAVES** -- **⇒⇒† AND
  **AND **THE **LEAVES **ARE **THE **ONES **THAT **DO **THE **WORK** (⇒⇒† AND **AND **THE **OUTPUT **IS
  **THE **SAME **BOOLEAN**)**."""
  # **⇒⇒† AND **THE **FIVE **FUNCTIONS **THAT **THE **CHAIN **CALLS**, **AND **THEIR **BODIES** (⇒⇒† AND
  # **AND **THE **LAST **ONE **IS **THE **BOOLEAN's **VALUE**)**.
  leaves = ["$_________tinybendygrad_renderer_cstyle_ku_inline2a",
            "$_________tinybendygrad_renderer_cstyle_ku_inline2b1",
            "$_________tinybendygrad_renderer_cstyle_ku_inline2b2a",
            "$_________tinybendygrad_renderer_cstyle_ku_inline2b2b"]
  # **⇒⇒† AND **THE **CHAIN's **EXACT **LOGIC**, **READ **FROM **THE **COMPILED **FORM**:
  # `ku_inline` = `and(or(not(is_cast), numel==1), ku_inline2)`
  # `ku_inline2` = `or(ku_inline2a, ku_inline2b)`
  # `ku_inline2b` = `or(ku_inline2b1, ku_inline2b2)`
  # `ku_inline2b2` = `or(ku_inline2b2a, ku_inline2b2b)`
  # `ku_inline2b1` = `and(is_load, ku_src_is_reg, cc==1)`
  # `ku_inline2b2` = `and(ku_inline2b2a, ku_inline2b2b)`
  # `ku_inline2b2a` = `and(or(is_cast, is_bitcast), or(is_global, is_local))`
  # `ku_inline2b2b` = `and(ku_inline_op_set, cc==1)`
  # `ku_inline2a` = `or(and(is_cast, ku_is_const_at), or(or(is_index, is_shrink), or(is_customi, is_refparam)))`
  # `ku_inline_op_set` = `or(is_stack, or(ku_is_alu_ex_where, or(is_cast, is_bitcast)))`
  name = "$_________tinybendygrad_renderer_cstyle_ku_inline"
  m = re.search(r"function (" + re.escape(name) + r")\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no ku_inline")
  fname, params = m.group(1), m.group(2)
  i, end = find_fn(src, fname)
  body = src[i:end]
  # **⇒⇒† AND **THE **COMPILED **FORM** **SHOWS **THAT **`Bool.and`/`Bool.or` **ARE **LAZY** (⇒⇒† AND **AND
  # **THE **PORT's **OWN **`Bool.pick` **WORK **RECORDS **THE **OPPOSITE **FOR **`Bool.pick`**, **⇒⇒† AND
  # **AND **THE **DIFFERENCE **IS **THAT **`Bool.pick`'s **ARMS **ARE **EAGER** (⇒⇒† AND **BOTH **ARMS **ARE
  # **BUILT**) **⇒⇒† AND **AND **`Bool.or`/`Bool.and` **SHORT-CIRCUIT** (⇒⇒† AND **THE **COMPILED **FORM
  # **IS **`($x || $y)`**)** -- **⇒⇒† AND **AND **SO **THE **FLAT **FORM **MUST **KEEP **THE **SHORTCIRCUIT**,
  # **⇒⇒† AND **AND **THE **NATIVE **`||` **AND **`&&` **DO **THAT**)**.
  #
  # **⇒⇒† AND **THE **CHAIN's **LOGIC**, **READ **FROM **THE **COMPILED **FORM**:
  # `ku_inline` = `and(or(not(is_cast), numel==1), ku_inline2)`
  # `ku_inline2` = `or(ku_inline2a, ku_inline2b)`
  # `ku_inline2b` = `or(ku_inline2b1, ku_inline2b2)`
  # `ku_inline2b2` = `or(ku_inline2b2a, ku_inline2b2b)`
  # `ku_inline2b2b` = `and(ku_inline_op_set, cc==1)`
  new = (f"function {fname}({params}) {{\n"
         f"  const _n = $$_________tinybendygrad_renderer_cstyle_KU_numel(_k_0);\n"
         f"  const _c = $$_________tinybendygrad_renderer_cstyle_is_cast(_op_0);\n"
         f"  if (!(_c || _n === 1)) return false;\n"
         f"  if ($$_________tinybendygrad_renderer_cstyle_ku_inline2a(_op_0, _k_0, _kus_0)) return true;\n"
         f"  if ($$_________tinybendygrad_renderer_cstyle_ku_inline2b1(_op_0, _k_0, _kus_0)) return true;\n"
         f"  if ($$_________tinybendygrad_renderer_cstyle_ku_inline2b2a(_op_0, _k_0)) return true;\n"
         f"  return ($$_________tinybendygrad_renderer_cstyle_ku_inline_op_set(_op_0) &&\n"
         f"          $$_________tinybendygrad_renderer_cstyle_cc_at(_k_0) === 1);\n"
         f"}}")
  return src[:i] + new + src[end:]


def build(name: str, s: str) -> pathlib.Path:
  s = s.replace(WALL_OLD, WALL_NEW).replace(DUMP_OLD, DUMP_NEW)
  p = BUILD / name
  p.write_text(s)
  return p


def main():
  import subprocess
  base = BUILD / "serve_plus.js"
  src = base.read_text()
  a = build("serve_in_base.js", src)
  b = build("serve_in_flat.js", patch(src))
  for p in (a, b):
    chk = subprocess.run(["node", "--check", str(p)], capture_output=True, text=True)
    if chk.returncode != 0:
      raise SystemExit(f"WARN: {p.name} does not parse:\n{chk.stderr[:600]}")
  print("THE BOTH BUILDS PARSE")

  dc = build("serve_in_noise.js", src)
  da = noisefloor.Daemon(a, "inbase")
  db = noisefloor.Daemon(b, "inflat")
  dd = noisefloor.Daemon(dc, "innoise")
  da.start()
  db.start()
  dd.start()
  time.sleep(1.2)
  for _ in range(150):
    da.turn()
    db.turn()
    dd.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()
  dd.stop()

  def walls(tag):
    p = pathlib.Path(str(BUILD.parent / f"nf-{tag}" / "cpu.json") + ".w")
    return sorted(w["w"] for w in json.loads(p.read_text()).get("W", []))

  A, B, C = walls("inbase"), walls("inflat"), walls("innoise")
  print()
  print("THE **RENDER's **WALL**, **THE **BASELINE**, **THE **FLAT **CHAIN**, **AND **THE **NOISE "
        "**FLOOR**:")
  print("  A (the baseline): min %.4f  median %.4f" % (A[0], A[len(A) // 2]))
  print("  B (the flat chain): min %.4f  median %.4f" % (B[0], B[len(B) // 2]))
  print("  C (the noise floor): min %.4f  median %.4f" % (C[0], C[len(C) // 2]))
  print()
  print("  **THE **CEILING**: the minima %.4f   the medians %.4f"
        % (B[0] / A[0], B[len(B) // 2] / A[len(A) // 2]))
  print("  **AND **THE **NOISE **FLOOR**: the minima %.4f   the medians %.4f"
        % (C[0] / A[0], C[len(C) // 2] / A[len(A) // 2]))


if __name__ == "__main__":
  main()
