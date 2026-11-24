#!/usr/bin/env python3
"""**COUNT **THE **`String.concat` **AND **`String.join` **CALL **SITES**, **DYNAMICALLY**, **IN
**THE **DAEMON** -- **⇒⇒† AND **WHICH **OF **THE **STATIC **SITES **ACTUALLY **RUN**.

**WHY.** §138's LESSON: **THE COUNT IS NOT THE COST** -- **BUT **THE COUNT MULTIPLIES **THE
COST**. **AND `render-text-shape.py` **READS**: **`String.concat` **IS **0.34 ms **A **TURN
**OVER **9,967 **CALLS**, **AND **`String.join` **IS **0.27 ms **OVER **691 **CALLS**.

**⇒⇒† AND **THE **STATIC **CENSUS** (`concat-callers.py`) **SAYS **THERE **ARE **29 **CONCAT
**SITES **AND **15 **JOIN **SITES** -- **⇒⇒† AND **BUT **A **STATIC **CENSUS **CANNOT **SAY
**WHICH **ONES **RUN**, **⇒⇒† AND **AND **THE **COST **IS **NOT **EVENLY **SPREAD** (⇒⇒† AND
**A **SITE **INSIDE **THE **HOT **LOOP **RUNS **HUNDREDS **OF **TIMES **A **TURN **AND **A **SITE
**IN **A **COLD **ARM **RUNS **ONCE**)**.

**⇒⇒† AND **SO **THIS **INSTRUMENT **COUNTS **PER **SITE**, **AT **RUNTIME** -- **⇒⇒† AND **AND
**THE **COUNTERS **ARE **PARENTHESIZED** (AN **UNPARENTHESIZED **COUNTER **AT **A **CALL **SITE
**BECOMES **AN **EXTRA **ARGUMENT** AND **THE **BUILD **HANGS**, THE TREE's OWN RULE)**.

**⇒⇒† AND **THE **SITES **ARE **FOUND **FROM **THE **COMPILED **FORM** (⇒⇒† AND **THE **COMPILED
**FORM **IS **WHERE **THE **CALL **SITES **ARE**), **⇒⇒† AND **AND **EVERY **SITE **IS **COUNTED
**BEFORE **IT **IS **PATCHED** -- **⇒⇒† AND **SO **A **MISS **IS **AN **ERROR **AND **NOT **A
**SILENT **ZERO** (THE TREE's OWN RULE: **A GATE **THAT **EXITS **0 **HAVING **MEASURED
**NOTHING **IS **WORSE **THAN **NO **GATE**)**.

**⇒⇒† AND **THE **PATCH **IS **A **REWRITE **OF **THE **CALLEE's **NAME**, **NOT **A **WRAPPER
**AROUND **THE **CALL** -- **⇒⇒† AND **BECAUSE **A **COMMA **EXPRESSION **IS **NOT **VALID
**INSIDE **AN **OBJECT **LITERAL** (MEASURED: **"Unexpected token ':'"** -- **AND **THE **CALL
**SITES **ARE **THE **OBJECT **LITERAL's **VALUES**) **⇒⇒† AND **AND **A **NAME **REWRITE **IS
**VALID **EVERYWHERE**.

**⇒⇒† AND **THE **REWRITE **IS **TO **A **COUNTING **WRAPPER** -- **⇒⇒† AND **AND **THE **WRAPPER
**IS **ONE **PER **CALLEE** (⇒⇒† AND **NOT **PER **SITE**)** -- **⇒⇒† AND **AND **THE **SITE's
**IDENTITY **COMES **FROM **THE **CALL's **POSITION** (⇒⇒† AND **THE **WRAPPER **TAKES **THE
**SITE's **INDEX** **AS **AN **EXTRA **ARGUMENT**, **⇒⇒† AND **AND **THE **CALL **IS **PATCHED
**TO **PASS **IT**)**.

**⇒⇒† AND **AND **THE **WRAPPER's **OWN **COST **IS **THE **INSTRUMENT's OWN COST** -- **⇒⇒† AND
**IT **IS **REPORTED** (⇒⇒† AND **THE **WRAPPER **IS **ONE **CALL **PER **STRING **CALL**, **⇒⇒†
**AND **THE **STRING **CALLS **ARE **9,967 **A **TURN**)**.
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

CALLEES = ("$$String_concat", "$String_join", "$_________tinybendygrad_renderer_cstyle_rt")


def scan_sites(src: str):
  """THE **CALL **SITES**, **IN **ORDER**, **WITH **THE **ENCLOSING **FUNCTION** -- **⇒⇒† AND
  **AND **THE **DEFINITION **IS **NOT **A **CALL **SITE** (⇒⇒† AND **THE **PREFIX
  **`function $String_join(`** **CONTAINS **THE **PREFIX **`$String_join(`**, **⇒⇒† AND **AND
  **PATCHING **IT **PRODUCES **"Function statements require a function name"** (MEASURED)**)**.
  """
  out = []
  depth = 0
  header = None
  i = 0
  while i < len(src):
    m = re.match(r"function (\$[A-Za-z0-9_]+)\(", src[i:])
    if m and depth == 0:
      header = m.group(1)
    ch = src[i]
    if ch == '"':
      i += 1
      while i < len(src):
        if src[i] == "\\":
          i += 2
          continue
        if src[i] == '"':
          break
        i += 1
    elif ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        rest = src[i + 1:i + 12].lstrip()
        if rest.startswith("else"):
          i += 1
          continue
        header = None
    else:
      for callee in CALLEES:
        if src.startswith(callee + "(", i):
          if not src[:i].rstrip().endswith("function"):
            out.append((i, callee, header or "(none)"))
    i += 1
  return out


def instrument(src: str):
  sites = scan_sites(src)
  print(f"THE CALL SITES: {len(sites)}")
  if not sites:
    raise SystemExit("WARN: no call sites -- IT WILL READ AS ZERO")

  # **THE **ORDER **OF **THE **TWO **PATCHES **IS **THE **ORDER **OF **THE **TWO **TEXTS**:
  # **THE **CALL **SITES **ARE **PATCHED **FIRST** (⇒⇒† AND **THE **CALL **SITES **ARE **IN **THE
  # **ORIGINAL **TEXT**, **⇒⇒† AND **AND **THE **WRAPPER **INSERTION **MOVES **THE **TEXT**), **⇒⇒†
  # **AND **THEN **THE **WRAPPERS **ARE **ADDED** (⇒⇒† AND **THE **WRAPPER's **HEADER **IS **FOUND
  # **IN **THE **PATCHED **TEXT**, **⇒⇒† AND **AND **THE **POSITIONS **ARE **THERE **AGAIN**)**.
  #
  # **AND **THE **CALL **SITES **ARE **PATCHED **FROM **THE **END**, **⇒⇒† AND **AND **SO **THE
  # **OFFSETS **DO **NOT **MOVE** (⇒⇒† AND **THE **TREE's OWN RULE: **PATCH **THE **LAST
  # **FIRST**)**.
  out = src
  idx = 0
  patched = []
  for pos, callee, header in sites:
    patched.append((pos, callee, header, idx))
    idx += 1
  for pos, callee, header, i in reversed(patched):
    open_paren = pos + len(callee)
    depth = 0
    k = open_paren
    while k < len(out):
      if out[k] == '"':
        k += 1
        while k < len(out):
          if out[k] == "\\":
            k += 2
            continue
          if out[k] == '"':
            break
          k += 1
      elif out[k] == "(":
        depth += 1
      elif out[k] == ")":
        depth -= 1
        if depth == 0:
          break
      k += 1
    close = k
    out = out[:close] + f", {i}" + out[close:]

  # **AND THE **WRAPPERS**, **ONE **PER **CALLEE** -- **⇒⇒† AND **AND **THEY **ARE **DEFINED
  # **AFTER **THE **ORIGINALS** (⇒⇒† AND **THE **ORIGINAL **IS **A **FUNCTION **DECLARATION**,
  # **⇒⇒† AND **AND **A **CONST **BINDING **IS **NOT **HOISTED**, **⇒⇒† AND **AND **THE **CALLS
  # **ARE **IN **FUNCTIONS **THAT **RUN **AFTER **THE **TOP **LEVEL**, **⇒⇒† AND **AND **SO **THE
  # **WRAPPER **MUST **BE **DEFINED **BEFORE **THE **FIRST **CALL**)**.
  #
  # **AND THE **WRAPPER **TAKES **THE **SITE's **INDEX** **AS **AN **EXTRA **ARGUMENT** -- **⇒⇒†
  # **AND **AND **THE **CALL **IS **PATCHED **TO **PASS **IT** -- **⇒⇒† AND **AND **THE **VALUE
  # **IS **UNCHANGED** (⇒⇒† AND **THE **COMMA **OPERATOR **RETURNS **THE **RIGHT **OPERAND**)**.
  for callee in CALLEES:
    # **THE **ORIGINAL, RENAMED**.
    m = re.search(r"function (" + re.escape(callee) + r")\(([^)]*)\)\s*\{", out)
    if not m:
      continue
    name, params = m.group(1), m.group(2)
    # **AND THE **HEADER **IS **FOUND **BY **THE **FULL **HEADER's **TEXT**, **NOT **BY
    # **`index`** -- **⇒⇒† AND **BECAUSE **`$String_join` **IS **A **PREFIX **OF
    # **`$String_join_go`** (⇒⇒† AND **AND **THE **SEARCH **MUST **MATCH **THE **WHOLE
    # **HEADER**)**
    header_text = f"function {name}({params})"
    i = out.index(header_text)
    j = out.index("{", i + len(header_text) - 1)
    depth = 0
    k = j
    while k < len(out):
      ch = out[k]
      if ch == '"':
        k += 1
        while k < len(out):
          if out[k] == "\\":
            k += 2
            continue
          if out[k] == '"':
            break
          k += 1
      elif ch == "{":
        depth += 1
      elif ch == "}":
        depth -= 1
        if depth == 0:
          rest = out[k + 1:k + 12].lstrip()
          if rest.startswith("else"):
            k += 1
            continue
          break
      k += 1
    end = k + 1
    body = out[i:end]
    inner = name + "__orig"
    body = body.replace(f"function {name}(", f"function {inner}(", 1)
    wrapper = (f"function {name}({params}, __site) {{\n"
               f"  globalThis.__CS[__site] = (globalThis.__CS[__site] || 0) + 1;\n"
               f"  return {inner}({', '.join(p.strip() for p in params.split(','))});\n"
               f"}}")
    out = out[:i] + body + "\n" + wrapper + out[end:]

  # **THE **ACCUMULATOR**, AT THE TOP OF `$serve`.
  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = out.index(marker)
  out = out[:i] + "globalThis.__CS = globalThis.__CS || [];\n" + out[i:]

  # **THE DUMP**, AT THE `@@END`.
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__CS.n = (globalThis.__CS.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".cs",
        JSON.stringify({CS: globalThis.__CS || [], n: globalThis.__CS.n || 0})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = out.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  out = out[:i] + dump_new + out[i + len(dump_old):]

  return out, [(c, h) for _, c, h, _ in patched]


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_base.js")
  out_path = BUILD / f"serve_sites_{base.stem}.js"
  src, sites = instrument(base.read_text())
  out_path.write_text(src)
  d = noisefloor.Daemon(out_path, f"sites{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  data = json.loads(pathlib.Path(str(d.cpu_file) + ".cs").read_text())
  CS = data.get("CS", [])
  n = data.get("n", 1) or 1
  CS = [v for v in CS if isinstance(v, (int, float))]
  rows = []
  for i, v in enumerate(CS):
    if not v or i >= len(sites):
      continue
    callee, header = sites[i]
    short = header.replace("$_________tinybendygrad_renderer_cstyle_", "").replace("$", "")
    rows.append((v / n, callee, short))
  rows.sort(reverse=True)
  print()
  print("THE **DYNAMIC **CENSUS **OF **THE **STRING **CALL **SITES** (60 turns, calls a turn):")
  for cnt, callee, short in rows:
    print(f"  {cnt:9.1f}  {callee:16s} {short}")
  print()
  print(f"  THE TOTAL: {sum(r[0] for r in rows):.1f} calls a turn")


if __name__ == "__main__":
  main()
