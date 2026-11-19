#!/usr/bin/env python3
"""**THE **PER-KERNEL **JOIN's **COST**, **MEASURED **IN **THE **DAEMON** -- **⇒⇒† AND **THE **SECOND
**O(n²) **JOIN**, **AND **THE **ONE **WITH **THE **BIGGEST **SINGLE **AMPLIFICATION**.

**⇒⇒† AND **THE **SITE**: **`render_kernel_body`** **DOES
**`String.concat([..., String.join(kernel, "\\n"), "\\n}"])`** -- **⇒⇒† AND **THE **`kernel`** **LIST
**IS **`List.reverse`d **FIRST** (⇒⇒† AND **SO **THE **JOIN **IS **RIGHT-NESTED **OVER **THE
**REVERSED **LIST**, **⇒⇒† AND **AND **THAT **IS **THE **WORST **CASE**: **THE **FIRST **LINE **IS
**COPIED **n **TIMES**)**.

**⇒⇒† AND **THE **PROBE **IS **AT **THE **COMPILED **`$String_join`** **AGAIN**, **⇒⇒† AND **AND **IT
**COUNTS **THE **LIST **AND **SUMS **THE **PREFIX **SUMS** -- **⇒⇒† AND **THE **SUM **OF **THE
**PREFIX **SUMS **IS **THE **EXACT **NUMBER **OF **CHARACTERS **THE **RIGHT-NESTED **JOIN **COPIES**
(⇒⇒† AND **A **LEFT-NESTED **ONE **COPIES **THE **HEAD **ONCE **PER **PIECE**, **⇒⇒† AND **SO **THE
**NUMBER **IS **THE **SAME **ORDER**, **⇒⇒† AND **AND **THE **PROBE **REPORTS **BOTH**).

**⇒⇒† AND **THE **PROBE **COUNTS **THE **JOIN's **ARGUMENT **LENGTH **PER **CALL**, **⇒⇒† AND **SO **A
**CALL **WITH **n **LINES **IS **ONE **ROW **OF **THE **TABLE**.
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


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, "globalThis.__K = {calls:0, lines:0, chars:0, copies:0, n:0, perCall:{}};\n" + old, 1)

  m = re.search(r"function \$String_join\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_join")
  par = src.index("(", m.start())
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
  _xs = src[par + 1:cp].split(",")[0].strip()
  # **⇒⇒† AND **THE **SEPARATOR's **LENGTH **IS **THE **SECOND **PARAMETER**, **⇒⇒† AND **AND **THE
  # **COPIES **COUNT **THE **SEPARATOR **TOO** (⇒⇒† AND **A **SEPARATOR **OF **ONE **CHAR **IS **COPIED
  # **ONCE **PER **PIECE**)**.
  _sep = src[par + 1:cp].split(",")[1].strip()
  probe = ("\n  { let __n = 0, __c = 0, __pre = 0, __cop = 0, __sl = 0, __x = " + _xs + ";"
          " while (__x && __x.$ === \"Con\") { __n += 1; __c += (__x.head || \"\").length;"
          " __pre += (__x.head || \"\").length; __cop += __pre; __x = __x.tail; }"
          " __sl = (" + _sep + " || \"\").length;"
          " globalThis.__K.calls += 1; globalThis.__K.lines += __n; globalThis.__K.chars += __c;"
          " globalThis.__K.copies += __cop + (__sl * (__n > 0 ? __n - 1 : 0));"
          " const __k = String(__n);"
          " globalThis.__K.perCall[__k] = (globalThis.__K.perCall[__k] || 0) + 1; }")
  src = src[:brace + 1] + probe + src[brace + 1:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__K.n = (globalThis.__K.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__K || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  src_js = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else BUILD / "live-e9c232cc6e361ca7.js"
  out = BUILD / "kernel_join_probe.js"
  out.write_text(instrument(src_js.read_text()))
  d = noisefloor.Daemon(out, "kjoin")
  d.start()
  time.sleep(0.8)
  for _ in range(20):
    d.turn()
  d.stop()
  K = json.loads((BUILD.parent / "nf-kjoin/cpu.json.d").read_text())
  n = max(K.get("n", 1), 1)
  calls = K.get("calls", 0) // n
  lines = K.get("lines", 0) // n
  chars = K.get("chars", 0) // n
  copies = K.get("copies", 0) // n
  print("THE `String.join` CALLS, BY LIST SIZE, MEASURED IN THE DAEMON:")
  per = {int(k): v // n for k, v in K.get("perCall", {}).items()}
  for k in sorted(per):
    print("  %4d items: %6d calls a turn" % (k, per[k]))
  print()
  print("  CALLS A TURN:              %d" % calls)
  print("  ITEMS A TURN:              %d" % lines)
  print("  ITEMS PER CALL:            %.1f" % (lines / max(calls, 1)))
  print("  CHARS OF TEXT A TURN:      %d" % chars)
  print("  CHARS COPIED A TURN:       %d" % copies)
  print("  THE AMPLIFICATION:         %.1fx" % (copies / max(chars, 1)))
  print()
  print("  =>=>+ AND **THE **PER-CALL **DISTRIBUTION **IS **THE **TABLE**: **A **CALL **WITH **n **ITEMS")
  print("  IS **ONE **JOIN, **AND **ITS **AMPLIFICATION **IS **~(n+1)/2**.")
