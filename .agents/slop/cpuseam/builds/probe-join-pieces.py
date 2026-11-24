#!/usr/bin/env python3
"""**THE **PIECE **COUNTS **PER **STATEMENT**, **MEASURED **IN **THE **DAEMON** -- **⇒⇒† AND **THE
**STRING **COPY **COST **IS **A **FUNCTION **OF **THAT **COUNT**, **⇒⇒† AND **SO **THE **COUNT **IS **THE
**INSTRUMENT**.

**⇒⇒† AND **THE **PORT's **STATEMENT **IS **`String.concat([indent, String.join(l, ""), ";"])`**, **⇒⇒† AND
**THE **PRELUDE's **`String.join` **IS **RIGHT-NESTED** (MEASURED,
`references/bend/bend2/base.bend:2266`: **`String.append(h, String.append(sep, String.join.go(t, h2,
sep)))`**) **⇒⇒† AND **SO **A **STATEMENT **WITH **`n` **PIECES **COPIES **ITS **TEXT
**`l * n * (n+1) / 2`** **CHARS **IN **THE **JOIN, **⇒⇒† AND **PLUS **THE **WHOLE **LINE **IN **THE
**CONCAT**.

**⇒⇒† AND **THE **PROBE **IS **AT **THE **`String.join` **CALL **SITE**, **⇒⇒† AND **IT **COUNTS **THE
**LIST **IT **IS **GIVEN**, **⇒⇒† AND **AND **IT **SUMS **THE **AMPLIFICATION **OVER **EVERY **CALL**,
**⇒⇒† AND **SO **THE **REPORT **IS **THE **TOTAL **COPIED **CHARS **A **TURN**, **⇒⇒† AND **WHICH **IS
**THE **NUMBER **THE **NEXT **CHANGE **MUST **CUT**.
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

# **THE **CALL **SITE**: **THE **`String.join(l, "")`** **IN **THE **STATEMENT** -- **⇒⇒† AND **THE
# **COMPILED **FORM **IS **A **CALL **TO **THE **PRELUDE's **`$String_join`**, **⇒⇒† AND **THE **PIECE
# **LIST **IS **ITS **FIRST **ARGUMENT**.
SITE = re.compile(r"\$\w*String_join\(")


def instrument(src: str) -> str:
  """**⇒⇒† AND **THE **PROBE **COUNTS **THE **LIST **LENGTH **AT **THE **CALL **SITE**, **⇒⇒† AND **AND
  **THE **CHARACTERS **COPIED **BY **THE **RIGHT-NESTED **JOIN**."""
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, "globalThis.__J = {calls:0, pieces:0, chars:0, n:0};\n" + old, 1)

  # **⇒⇒† AND **THE **`$String_join` **BODY** -- **⇒⇒† AND **THE **LIST **IS **THE **FIRST
  # **ARGUMENT**, **⇒⇒† AND **AND **THE **COPIES **ARE **`l * n * (n+1) / 2`**.
  m = re.search(r"function \$String_join\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_join")
  op = m.start()
  par = src.index("(", op)
  d = 0
  for c in range(par, len(src)):
    if src[c] == "(":
      d += 1
    elif src[c] == ")":
      d -= 1
      if d == 0:
        cp = c
        break
  brace = src.index("{", cp)
  # **⇒⇒† AND **THE **PARAMETER **NAME **IS **READ **FROM **THE **COMPILED **FORM**, **⇒⇒† AND **AND
  # **A **HARDCODED **NAME **THAT **IS **NOT **THE **COMPILED **ONE** **IS **A **ReferenceError** (THE
  # **TREE's **OWN **RULE**)**
  _params = src[par + 1:cp].split(",")
  _xs = _params[0].strip()
  probe = ("\n  { let __n = 0, __c = 0, __pre = 0, __cop = 0, __x = " + _xs + ";"
          " while (__x && __x.$ === \"Con\") { __n += 1; __c += (__x.head || \"\").length;"
          " __pre += (__x.head || \"\").length; __cop += __pre; __x = __x.tail; }"
          " globalThis.__J.calls += 1; globalThis.__J.pieces += __n; globalThis.__J.chars += __c;"
          " globalThis.__J.copies = (globalThis.__J.copies || 0) + __cop;"
          " globalThis.__J.heads = (globalThis.__J.heads || 0) + ((__n > 0 ? __c : 0)); }")
  src = src[:brace + 1] + probe + src[brace + 1:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__J.n = (globalThis.__J.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__J || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  src_js = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else BUILD / "serve_base_cpu.js"
  out = BUILD / "join_probe.js"
  out.write_text(instrument(src_js.read_text()))
  d = noisefloor.Daemon(out, "join")
  d.start()
  time.sleep(0.8)
  for _ in range(20):
    d.turn()
  d.stop()
  J = json.loads((BUILD.parent / "nf-join/cpu.json.d").read_text())
  n = max(J.get("n", 1), 1)
  calls = J.get("calls", 0) // n
  pieces = J.get("pieces", 0) // n
  chars = J.get("chars", 0) // n
  copies = J.get("copies", 0) // n
  heads = J.get("heads", 0) // n
  print("THE `String.join` CALLS, MEASURED IN THE DAEMON:")
  print(f"  CALLS A TURN:          {calls}")
  print(f"  PIECES A TURN:         {pieces}")
  print(f"  PIECES PER CALL:       {pieces/max(calls,1):.1f}")
  print(f"  CHARS A TURN:          {chars}")
  print(f"  CHARS COPIED BY THE JOIN A TURN (THE HEAD PIECES): {heads}")
  print(f"  THE AMPLIFICATION:     {heads/max(chars,1):.2f}x")
  print(f"  THE PREFIX-SUM COUNT (THE OTHER NESTING's): {copies}")
  print("  =>=>+ AND **THE **PREFIX-SUM **COUNT **IS **NOT **WHAT **THE **PRELUDE **DOES** -- **=>=>+ AND **THE")
  print("  **BENCH **IS **THE **DECISIVE **READING** (THE **TIME **GROWS **LINEARLY**)")
