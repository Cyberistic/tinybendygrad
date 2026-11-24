#!/usr/bin/env python3
"""**CLOCK **THE **DECIMAL **CONVERSIONS**, **IN **THE **DAEMON** -- **⇒⇒† AND **AND **THE **INTEGER
**CONSTANTS **ARE **RENDERED **BY **DIVISION**, **ONE **DIGIT **AT **A **TIME**.

**WHY.** `cstyle.bend:1875`: **`ku_const_cast_int`** **PASSES **`H.i64_dec(i)`** **IN**, **⇒⇒† AND **AND
**THE **COMMENT **RECORDS **THAT **THIS **IS **A **MEASURED **CHANGE** (⇒⇒† AND **THE **OLD **SPELLING
**CALLED **IT **SEVEN **TIMES **PER **CONSTANT**)** -- **⇒⇒† AND **AND **THE **DECIMAL **IS **BUILT **BY
**DIVISION** (⇒⇒† AND **`i64_dec.go` **IS **A **RECURSION **THAT **DIVIDES **BY **TEN**)**.

**⇒⇒† AND **AND **`i64_dec.trim` **USES **A **`Bool.pick`** (⇒⇒† AND **WHOSE **ARMS **ARE **EAGER**),
**⇒⇒† AND **AND **THE **`Bool.pick`'s **CURE **IS **THE **TREE's OWN**: **A **`match` **ON **A **BOOL
**PARAMETER** (⇒⇒† AND **§39**) -- **⇒⇒† AND **AND **THE **TRIM **IS **A **WALK **OVER **THE **DIGITS**.
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

ACC = """globalThis.__D = globalThis.__D || {};
globalThis.__DM = (k, t0) => { globalThis.__D[k] = (globalThis.__D[k] || 0) + (performance.now() - t0); };
globalThis.__DN = (k) => { globalThis.__D[k + ".n"] = (globalThis.__D[k + ".n"] || 0) + 1; };"""


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


def instrument(src: str) -> str:
  # **THE **FAMILIES**, **BY **THEIR **COMPILED **NAME** -- **⇒⇒† AND **AND **THE **POPULATION **IS
  # **DISCOVERED **FROM **THE **COMPILED **FORM** (⇒⇒† AND **AND **NOT **FROM **A **HAND **LIST**)**.
  found = sorted(set(re.findall(r"function (\$_________tinybendygrad_helpers_[A-Za-z0-9_]*(?:i64_dec|u32_dec|"
                                r"i64_of_i32|lo32|divmod_[a-z]+|u64_divmod)[A-Za-z0-9_]*)\(", src)))
  print(f"THE DECIMAL FUNCTIONS: {len(found)}")
  out = src
  for name in found:
    m = re.search(r"function (" + re.escape(name) + r")\(([^)]*)\)\s*\{", out)
    if not m:
      continue
    fname, params = m.group(1), m.group(2)
    i, end = find_fn(out, fname)
    if i is None:
      continue
    body = out[i:end]
    inner = fname + "__orig"
    body = body.replace(f"function {fname}(", f"function {inner}(", 1)
    args = ", ".join(p.strip() for p in params.split(","))
    key = fname.replace("$_________tinybendygrad_helpers_", "")
    wrapper = (f"function {fname}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  globalThis.__DN(\"{key}\");\n"
               f"  const __v = {inner}({args});\n"
               f"  globalThis.__DM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    out = out[:i] + body + "\n" + wrapper + out[end:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = out.index(marker)
  out = out[:i] + ACC + "\n" + out[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".dd",
        JSON.stringify({D: globalThis.__D || {}})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = out.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  out = out[:i] + dump_new + out[i + len(dump_old):]
  return out


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_plus.js")
  out_path = BUILD / f"serve_dec_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"dec{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".dd").read_text())
  D = data.get("D", {})
  n = 60
  rows = []
  for k, v in D.items():
    if k.endswith(".n"):
      continue
    cnt = D.get(k + ".n", 0) / n
    if cnt <= 0:
      continue
    rows.append((v / n, cnt, k))
  rows.sort(reverse=True)
  print()
  print("THE **DECIMAL **CONVERSIONS**, **IN THE DAEMON** (60 turns):")
  print("  %9s %9s  %s" % ("ms a turn", "calls", "THE FUNCTION"))
  for ms, cnt, k in rows[:14]:
    print("  %9.4f %9.1f  %s" % (ms, cnt, k))
  print()
  print(f"  THE TOTAL: {sum(r[0] for r in rows):.4f} ms a turn (THE ARMS ARE NESTED, SO THEY DO NOT SUM)")


if __name__ == "__main__":
  main()
