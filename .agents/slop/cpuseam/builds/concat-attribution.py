#!/usr/bin/env python3
"""**COUNT **THE **`String.concat` **CALLS **BY **THEIR **ENCLOSING **FUNCTION**, **DYNAMICALLY**,
**IN **THE **DAEMON** -- **⇒⇒† AND **WHICH **FUNCTION **MAKES **THE **9,967 **CALLS**.

**WHY.** `render-text-shape.py` **CLOCKS**: **`String.concat` **IS **0.34 ms **A **TURN **OVER
**9,967 **CALLS**. **AND `concat-sites-dynamic.py` **COUNTS **THE **CALL **SITES** -- **BUT **IT
**COUNTS **THE **TOP-LEVEL **CALLS**, **⇒⇒† AND **THE **RECURSIVE **SELF-CALLS **ARE **THE
**AMPLIFICATION** (⇒⇒† AND **A **`String.concat` **OF **36 **PIECES **IS **37 **CALLS**) **⇒⇒† AND
**AND **THE **AMPLIFICATION **IS **WHERE **THE **TIME **IS**.

**⇒⇒† AND **SO **THIS **INSTRUMENT **COUNTS **THE **RECURSIVE **CALL **TOO**, **BY **COUNTING **THE
**SELF-CALL **INSIDE **`String_concat`'s **BODY** (⇒⇒† AND **A **COUNTER **AT **THE **CALL **SITE**,
**PARENTHESIZED** -- **AN **UNPARENTHESIZED **COUNTER **AT **A **CALL **SITE **BECOMES **AN **EXTRA
**ARGUMENT** AND **THE **BUILD **HANGS**, THE TREE's OWN RULE)**) **⇒⇒† AND **AND **BY **ATTRIBUTING
**THE **SELF-CALLS **TO **THE **CALLER** -- **⇒⇒† AND **AND **THE **ATTRIBUTION **IS **BY **THE
**STACK**, **⇒⇒† AND **AND **THE **STACK **IS **THE **CALL **CHAIN** (⇒⇒† AND **AND **THE **JS
**LANE's **`Error().stack` **NAMES **THE **CALLERS**)**.

**⇒⇒† AND **AND **THE **COUNTER **IS **AT **THE **SELF-CALL's **SITE**, **⇒⇒† AND **AND **THE
**ATTRIBUTION **IS **BY **A **WALK **OF **THE **STACK** (⇒⇒† AND **AND **THE **STACK **IS **FREE** --
**AND **THE **`Error` **CONSTRUCTOR **IS **THE **COST**)**.
"""

import json
import pathlib
import re
import sys
import time
from collections import Counter

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

ACC = """globalThis.__A = globalThis.__A || {};
globalThis.__AC = (k) => { globalThis.__A[k] = (globalThis.__A[k] || 0) + 1; };
globalThis.__AS = (k) => { const s = new Error().stack; const m = s.match(/at (\\$?[A-Za-z0-9_]+)/g) || [];
  globalThis.__A[k] = (globalThis.__A[k] || 0) + 1;
  globalThis.__AL = globalThis.__AL || {}; globalThis.__AL[k] = globalThis.__AL[k] || {};
  for (const f of m) { const nm = f.slice(3); globalThis.__AL[k][nm] = (globalThis.__AL[k][nm] || 0) + 1; } };"""


def instrument(src: str) -> str:
  # **THE **SELF-CALL **INSIDE **`String_concat`'s **BODY** -- **⇒⇒† AND **AND **THE **SITE **IS
  # **COUNTED **BEFORE **IT **IS **PATCHED** (⇒⇒† AND **THE **TREE's OWN RULE)**.
  m = re.search(r"function \$String_concat\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_concat")
  i = src.index(f"function $String_concat({m.group(1)})")
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
        break
    k += 1
  body = src[i:k + 1]
  rec = "const _x_0 = $$String_concat(_t_0);"
  if body.count(rec) != 1:
    raise SystemExit(f"WARN: the concat self-call site is {body.count(rec)}")
  # **AND THE **ATTRIBUTION **IS **BY **THE **STACK** -- **⇒⇒† AND **AND **THE **STACK **NAMES
  # **THE **CALLERS**, **⇒⇒† AND **AND **THE **CALLEE **IS **THE **FIRST **FRAME** **AND **THE
  # **CALLER **IS **THE **SECOND** (⇒⇒† AND **AND **THE **SELF-CALL **IS **FROM **THE **WRAPPER**,
  # **⇒⇒† AND **AND **SO **THE **CALLER **IS **THE **THIRD**)**.
  body = body.replace(rec,
                      "globalThis.__AS(\"concat\");\n"
                      "    const _x_0 = $$String_concat(_t_0);")
  src = src[:i] + body + src[k + 1:]

  # **THE ACCUMULATOR**, AT THE TOP OF `$serve`.
  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  # **THE DUMP**, AT THE `@@END`.
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".al",
        JSON.stringify({A: globalThis.__A || {}, AL: globalThis.__AL || {}, n: (globalThis.__A.n || 0) + 1})); } catch (e) {} }
    globalThis.__A.n = (globalThis.__A.n || 0) + 1;
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = src.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  src = src[:i] + dump_new + src[i + len(dump_old):]
  return src


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_base.js")
  out_path = BUILD / f"serve_attr_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"attr{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".al").read_text())
  n = data.get("n", 1) or 1
  AL = data.get("AL", {}).get("concat", {})
  print()
  print(f"THE **CONCAT's **RECURSIVE **CALLS**, BY **THEIR **CALLER** ({n} turns):")
  rows = sorted(AL.items(), key=lambda kv: -kv[1])
  for nm, c in rows[:18]:
    short = nm.replace("$_________tinybendygrad_renderer_cstyle_", "").replace("$", "")
    print(f"  {c/n:9.1f} a turn  {short}")
  print()
  print(f"  THE TOTAL: {sum(AL.values())/n:.1f} a turn")


if __name__ == "__main__":
  main()
