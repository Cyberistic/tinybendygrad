#!/usr/bin/env python3
"""CLOCK **EACH `arg_of` ARM** SEPARATELY, **INSIDE** THE DAEMON.

**WHY:** THE `arg_of` PHASE READS **0.232 ms** AND THE **DISPATCH** IS **ONLY 0.002 ms**
(MEASURED, `builds/probe-argof-cost.js`: THE CHAIN'S OWN COST ON THE REAL KIND SEQUENCE IS
**0.0020 ms** -- **0.9% OF THE PHASE**). **⇒⇒⇒ SO THE COST IS IN **THE ARMS' BODIES**, AND
**WHICH ARM** IS **NOT** KNOWN BY INSPECTION -- IT MUST BE **MEASURED**.

**AND EVERY PATCH SITE IS **COUNTED BEFORE IT IS APPLIED**, SO A MISS IS **AN ERROR** AND NOT
**A SILENT ZERO** -- BECAUSE **A CLOCK THAT FIRES ON NOTHING READS AS ZERO AND A ZERO IS
**NOT** A MEASUREMENT.**

**THE MECHANISM:** EACH ARM'S RETURN IS **ONE DISTINGUISHING SUBSTRING**, AND **EACH IS
**COUNTED** BEFORE IT Is PATCHED. THE CLOCK IS **AT THE RETURN**, SO IT MEASURES **THE ARM's
BODY** (WHATEVER THE ARM DID BEFORE IT RETURNED) AND **NOT** THE DISPATCH.
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

ACC = ("globalThis.__D = globalThis.__D || {none:0, const:0, constint:0, param:0, index:0,"
       " sink:0, special:0, range:0, wmma:0, n:0};\n"
       "globalThis.__M = (k, t0) => { globalThis.__D[k] += (performance.now() - t0); };")

# (THE KEY, THE SUBSTRING THAT IDENTIFIES THE ARM, AND **HOW MANY TIMES IT MUST APPEAR**).
ARMS = [
  ("none", 'return {$: "KANone"};', 9),
  ("const", 'return {$: "KAConst"', 2),
  ("constint", 'return $_________tinybendygrad_renderer_live_const_int_of(', 1),
  ("param", 'return $_________tinybendygrad_renderer_live_param_of(', 1),
  ("index", 'return {$: "KAIndex"', 1),
  ("sink", 'return {$: "KASink"', 1),
  ("special", 'return $_________tinybendygrad_renderer_live_special_of(', 1),
  ("range", 'return $_________tinybendygrad_renderer_live_arg_of_range(', 1),
  ("wmma", 'return $_________tinybendygrad_renderer_live_arg_of_wmma(', 1),
]

# **THE CLOCK IS **AT THE RETURN**, SO IT MEASURES **THE ARM's BODY** -- AND THE BODY IS
# **THE EXPRESSION IN THE RETURN**. SO THE CLOCK IS PUT **AROUND THE EXPRESSION**, WHICH
# MEANS **THE `const`/`param`/`index`/`sink`/`special` ARMS' EXPRESSIONS ARE EVALUATED
# **AFTER** THE CLOCK'S START, WHICH IS **WHAT WE WANT**: THE CLOCK SHOULD MEASURE THE ARM.
#
# ⇒⇒⇒ SO: `return EXPR;` BECOMES `return (() => { const __t = performance.now(); const __v = EXPR;
# globalThis.__M("key", __t); return __v; })();`
ARROW = ('return (() => { const __t = performance.now(); const __v = ')


def instrument(src: str) -> str:
  """THE ACCUMULATOR, AT THE TOP OF `$serve`."""
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  # **THE `arg_of` BODY, AND **ONLY** IT** -- BECAUSE `KANone` APPEARS 18 TIMES IN THE
  # BUILD (THE MASKS, THE RANGE's AND THE WMMA's FALLBACKS) AND **ONLY** THE ONES **INSIDE
  # `arg_of` ARE THE ARMS BEING MEASURED.**
  NAME = "function $_________tinybendygrad_renderer_live_arg_of("
  i = src.index(NAME)
  j = src.index("{", i)
  depth = 0
  for k in range(j, len(src)):
    if src[k] == "{":
      depth += 1
    elif src[k] == "}":
      depth -= 1
      if depth == 0:
        break
  body = src[i:k + 1]

  # **EACH ARM**, COUNTED FIRST.
  for key, marker, want in ARMS:
    n = body.count(marker)
    if n != want:
      raise SystemExit(f"WARN: the {key} arm is {n} (want {want})")
    for _ in range(n):
      idx = body.index(marker)
      expr_start = idx + len("return ")
      j2 = body.index(";", expr_start)
      expr = body[expr_start:j2]
      body = (body[:expr_start]
              + f'(() => {{ const __t = performance.now(); const __v = {expr};'
              + f' globalThis.__M("{key}", __t); return __v; }})()'
              + body[j2:])

  out = src[:i] + body + src[k + 1:]

  # **THE DUMP**, AT THE `@@END` SITE.
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__D || {})); } catch (e) {} }
    globalThis.__D.n = (globalThis.__D.n || 0) + 1;
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if out.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {out.count(dump_old)}")
  return out.replace(dump_old, dump_new, 1)


if __name__ == "__main__":
  base = BUILD / "serve_base.js"
  out = BUILD / "serve_armof.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "armof")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  d.stop()
  D = json.loads((BUILD.parent / "nf-armof/cpu.json.d").read_text())
  n = max(D.get("n", 1), 1)
  print(f"\nEACH `arg_of` ARM, **IN THE DAEMON** ({n} turns), ms a turn:")
  tot = 0.0
  for key, _, _ in ARMS:
    v = D.get(key, 0.0) / n
    tot += v
    print(f"  {key:9s} {v:.4f}")
  print(f"  {'TOTAL':9s} {tot:.4f}   (THE `arg_of` PHASE READS **0.2320 ms**)")
  print(f"\nAND THE **DISPATCH** IS **0.0020 ms** (MEASURED, `probe-argof-cost.js`), SO THE")
  print(f"**ARMS' BODIES** ARE **{tot:.4f} ms** AND THE **DISPATCH** IS **0.0020 ms**.")
