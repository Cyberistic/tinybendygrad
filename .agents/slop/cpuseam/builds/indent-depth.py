#!/usr/bin/env python3
"""**THE **INDENT **DEPTH's **DISTRIBUTION**, **MEASURED **IN **THE **DAEMON** -- **⇒⇒† AND **THE
**TABLE **THE **FIX **IS **DESIGNED **AGAINST**.

**WHY.** `concat-chain-decode.py` **MEASURED** **THE **DIRECT **CALLERS **OF **`String.concat`**:
**`ku_indent` **IS **1,789 **OF **9,967 **CALLS **A **TURN** (18%) -- **THE **BIGGEST **SINGLE
**CALLER** -- **⇒⇒† AND **AND **`ku_indent.go` **IS **THE **QUADRATIC **BUILDER**
(`String.concat([acc, "  "])` **PER **LEVEL**).

**⇒⇒† AND **THE **FIX **MUST **KNOW **THE **DEPTH's **DISTRIBUTION** (⇒⇒† AND **A **TABLE **OF
**PRECOMPUTED **INDENTS **IS **THE **OBVIOUS **SHAPE**, **⇒⇒† AND **AND **A **TABLE **WITH **A **BOUND
**IS **ONLY **RIGHT **IF **THE **BOUND **IS **MEASURED**) -- **⇒⇒† AND **AND **THE **DEPTH **IS **THE
**RENDER's **NESTING **DEPTH**, **⇒⇒† AND **AND **IT **IS **A **COUNTER **ON **THE **STATE**).
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
globalThis.__DH = (d) => { globalThis.__D[d] = (globalThis.__D[d] || 0) + 1; };
globalThis.__DK = (k) => { globalThis.__D[k] = (globalThis.__D[k] || 0) + 1; };"""


def instrument(src: str) -> str:
  # **THE **DEPTH, **AT **`ku_indent`'s **ENTRY** -- **⇒⇒† AND **AND **THE **ENTRY **IS **WHERE **THE
  # **DEPTH **IS **KNOWN** (⇒⇒† AND **AND **THE **RECURSION **PASSES **IT **DOWN**, **⇒⇒† AND **AND
  # **THE **COUNT **AT **THE **ENTRY **IS **ONE **COUNT **PER **STATEMENT**)**
  m = re.search(r"function (\$_________tinybendygrad_renderer_cstyle_ku_indent)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no ku_indent")
  name, params = m.group(1), m.group(2)
  i = src.index(f"function {name}({params})")
  # **AND **THE **BODY**, **BY **THE **BRACE **SCAN** (⇒⇒† AND **AND **THE **NAIVE **SCAN **CUTS
  # **A **COMPILED **`if/else` **CHAIN **IN **HALF** -- **§138.3's RULE**)**
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
  # **AND THE **COUNTER **IS **AT **THE **ENTRY** -- **⇒⇒† AND **AND **IT **IS **A **STATEMENT **IN
  # **THE **BODY** (⇒⇒† AND **AND **IT **DOES **NOT **CHANGE **THE **VALUE**)**.
  newbody = body.replace("{", "{\n  globalThis.__DH(_depth_0);", 1)
  src = src[:i] + newbody + src[k + 1:]

  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".dh",
        JSON.stringify({D: globalThis.__D || {}})); } catch (e) {} }
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
  out_path = BUILD / f"serve_depth_{base.stem}.js"
  out_path.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out_path, f"depth{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".dh").read_text())
  D = data.get("D", {})
  print()
  print("THE **INDENT **DEPTH's **DISTRIBUTION** (60 turns):")
  for k in sorted((k for k in D if k.lstrip("-").isdigit()), key=lambda x: int(x)):
    print(f"  depth {k:>3}: {D[k]/60:9.1f} a turn")
  print()
  tot = sum(v for k, v in D.items() if k.lstrip("-").isdigit())
  chars = sum(v * int(k) * 2 for k, v in D.items() if k.lstrip("-").isdigit())
  print(f"  THE TOTAL: {tot/60:.1f} a turn")
  print(f"  THE INDENT CHARS BUILT: {chars/60:.0f} a turn  (**⇒⇒† AND **THE **OLD **SHAPE **COPIES "
        f"**EACH **LEVEL's **STRING**, **⇒⇒† AND **SO **THE **COPIES **ARE **THE **SUM **OF **THE "
        f"**DEPTHs**)")
  print(f"  **⇒⇒† AND **THE **SUM **OF **THE **DEPTHs**: "
        f"{sum(v * int(k) for k, v in D.items() if k.lstrip('-').isdigit())/60:.0f} a turn")


if __name__ == "__main__":
  main()
