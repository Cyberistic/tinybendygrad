#!/usr/bin/env python3
"""CLOCK THE **RENDER's** **STRING **WORK**, **INSIDE** THE DAEMON.

**WHY THIS FILE EXISTS.** §138.3's `render-shape.py` CLOCKS THE RENDER's PARTS, BUT **THE
RECURSIVE FAMILIES ARE **COUNTED **AND **NOT **CLOCKED** -- `text` (16 FUNCTIONS, THROUGH
`ku_text_go`) AND `inline` (9, THROUGH `ku_inline2`) -- **BECAUSE **A **WRAPPER **LAYER **IS
**PAID **AT **EVERY **RECURSION **LEVEL** (MEASURED: WRAPPING ALL **46** READS `render` AT
**13.34 ms** AGAINST **THE TRUE 1.04 ms**).

**SO THE STRING WORK IS CLOCKED **AT **THE **PRELDE's **OWN **FUNCTIONS** INSTEAD** -- `String.concat`,
`String.join`, `String.append` -- **BECAUSE **THOSE **ARE **THE **LEAVES** (THE **TEXT **IS **MADE
OF **THEM**), **AND **THEY **ARE **NOT **RECURSIVE **THEMSELVES** (THE **RECURSION **IS **THE
**LIST**, **AND **THE **LIST **WALK **IS **ONE **CALL **PER **PIECE**)**.

**AND EVERY PATCH SITE IS **READ **FROM **THE **COMPILED **FORM** AND **COUNTED **BEFORE **IT
IS **APPLIED** -- **SO A **MISS **IS **AN **ERROR **AND **NOT **A **SILENT **ZERO** (THE TREE's OWN
RULE: **A GATE **THAT **EXITS **0 **HAVING **MEASURED **NOTHING **IS **WORSE **THAN **NO **GATE**).

**AND THE CLOCK IS **INSIDE** THE FUNCTION BODY, BECAUSE **A REST-ARGUMENTS WRAPPER IS NOT
FREE** (MEASURED, §136: WRAPPING SEVEN FUNCTIONS MOVED THE RENDER **2.265 ms -> 3.494 ms**).

**AND THE ACCUMULATOR IS READ AT THE `@@END`, WHICH FIRES **ONCE **A **TURN**.

**AND THE INSTRUMENT's OWN COST IS **MEASURED **ON **THE **SAME **DUMP** -- THE **SHAPED
BUILD's **RENDER **WALL** AND **THE **PLAIN **BUILD's **RENDER **WALL** ARE **BOTH **REPORTED**,
SO **THE **DIFFERENCE **IS **THE **INSTRUMENT's OWN COST** AND IT IS **VISIBLE **AND **NOT
HIDDEN**.
"""

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

ACC = """globalThis.__S = globalThis.__S || {};
globalThis.__SM = (k, t0) => { globalThis.__S[k] = (globalThis.__S[k] || 0) + (performance.now() - t0); };
globalThis.__SN = (k) => { globalThis.__S[k + ".n"] = (globalThis.__S[k + ".n"] || 0) + 1; };"""

# THE **PRELDE's **STRING **FUNCTIONS**, AND **WHAT **EACH **COSTS**.
#
# `String.concat` AND `String.join` ARE **THE **TWO **THE **RENDER **USES**, AND **THEY **ARE
# **THE **LEAVES** -- **THE **TEXT **IS **MADE **OF **THEM**.
#
# AND `String.join_go` IS **THE **RECURSIVE **ONE** -- **SO **IT **IS **COUNTED **AND **NOT
# **CLOCKED** (A **WRAPPER **LAYER **PER **LEVEL**), **AND **THE **COUNT **IS **THE
# **MULTIPLIER** (§138's LESSON: **THE COUNT IS NOT THE COST**, **BUT **THE COUNT MULTIPLIES
# **THE COST**).
TARGETS = [
  ("concat", "$String_concat"),
  ("join", "$String_join"),
]

# **THE **INDENT**, **CLOCKED **AT **ITS **ENTRY** -- **⇒⇒† AND **THE **ENTRY **IS **NOT
# **RECURSIVE** (⇒⇒† AND **THE **RECURSION **IS **`ku_indent_go`'s**), **⇒⇒† AND **AND **THE
# **ENTRY's **CLOCK **SPANS **THE **WHOLE **INDENT** (⇒⇒† AND **AND **THE **`go` **BODY **IS **THE
# **WORK**)**.
#
# **⇒⇒† AND **THE **INDENT **IS **THE **BIGGEST **CALLER **OF **`String.concat`** (⇒⇒† AND
# **MEASURED: **1,789 **OF **9,967 **CALLS **A **TURN**), **⇒⇒† AND **SO **IT **IS **HERE**."""
INDENT = "_________tinybendygrad_renderer_cstyle_ku_indent"


def find_fn(src: str, compiled: str):
  """THE COMPILED FUNCTION, BY ITS **COMPILED NAME**, AND **WHERE IT ENDS**.

  **AND THE END IS **NOT** "THE FIRST `}` AT DEPTH 0" -- BECAUSE **A COMPILED `if/else` CHAIN
  HAS **A `}` AT DEPTH 0** IN THE MIDDLE** (THE `}` THAT CLOSES THE FIRST BRANCH, WITH THE
  `else if` FOLLOWING IT). MEASURED: THE NAIVE SCAN CUT `ku_text_go` **IN HALF**, AND THE
  REWRITTEN SOURCE DID NOT EVEN PARSE ("Unexpected else").
  """
  marker = f"function {compiled}("
  i = src.find(marker)
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


def instrument(src: str):
  # **THE SITES ARE **COUNTED **BEFORE **THEY **ARE **APPLIED** -- **SO A **MISS **IS **AN
  # **ERROR **AND **NOT **A **SILENT **ZERO**.
  #
  # **AND BOTH **OF **THE **PRELDE's **STRING **FUNCTIONS **ARE **RECURSIVE** (`$String_concat`
  # **CALLS **ITSELF**, AND `$String_join` **CALLS `$String_join_go`** **WHICH **CALLS **ITSELF**)
  # -- **SO **A **WRAPPER **IS **NOT **AVAILABLE **FOR **EITHER** (A **WRAPPER **OF **A
  # **RECURSIVE **FUNCTION **RECURSES **INTO **THE **WRAPPER** **AND **THE **HOST **STACK
  # **OVERFLOWS** -- MEASURED: "memory fault (machine stack overflow?)")**.
  #
  # **SO THE COST IS **CLOCKED **INSIDE **THE **BODY** -- **AT **THE **RECURSIVE **CALL's
  # **SITE** -- **AND **THE **CLOCK **SPANS **THE **REST **OF **THE **BODY** (THE **TAIL **OF
  # **THE **LIST**, **WHICH **IS **THE **WORK**)**. **AND THE **COUNTS **ARE **AT **THE
  # **SITES**, **PARENTHESIZED** (AN **UNPARENTHESIZED **COUNTER **AT **A **CALL **SITE
  # **BECOMES **AN **EXTRA **ARGUMENT** AND **THE **BUILD **HANGS**, THE TREE's OWN RULE)**.
  sites = []
  for key, name in TARGETS:
    found = sorted(set(re.findall(r"function (\$" + re.escape(name[1:]) + r"[A-Za-z0-9_]*)\(", src)))
    if not found:
      raise SystemExit(f"WARN: the {key} family is 0 -- IT WILL READ AS ZERO")
    sites.append((key, found))
  print(f"THE SITES: {sum(len(n) for _, n in sites)}")
  for key, names in sites:
    print(f"  {key:8s} {len(names)}  ({', '.join(names)})")

  # **THE **`concat` **CLOCK**, **INSIDE **THE **BODY** -- **AT **THE **RECURSIVE **CALL's
  # **SITE**, **AND **THE **CLOCK **SPANS **THE **REST **OF **THE **BODY** (THE **TAIL)**.
  #
  # **AND THE **CLOCK **MUST **NOT **SPAN **THE **RECURSIVE **CALL** -- **BECAUSE **THE
  # **OUTER **CALL's **CLOCK **WOULD **SPAN **THE **WHOLE **LIST** **AND **THE **INNER **ONE
  # **SPANS **THE **REST**, **AND **SO **THE **SUM **WOULD **COUNT **THE **NESTED **PARTS **TWICE**
  # (**A **NESTED **CLOCK **IS **A **CLOCK **AND **A **SUM**).
  #
  # **SO THE **CLOCK **SPANS **ONLY **THE **BODY's **OWN **WORK** -- **THE **NATIVE **CONCAT**
  # (`_h_0 + _x_0`) **AND **NOT **THE **RECURSION** -- **AND **THE **RECURSION's **OWN **WORK **IS
  # **COUNTED **BY **THE **INNER **CALL's **CLOCK** (**⇒⇒† AND **THE **INNER **CLOCK **IS **THE
  # **OUTER **ONE's **CHILD**, **⇒⇒† AND **AND **THE **TWO **CLOCKS **DO **NOT **OVERLAP**)**.
  m = re.search(r"function (\$String_concat)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_concat")
  i, end = find_fn(src, "$String_concat")
  body = src[i:end]
  rec = "const _x_0 = $$String_concat(_t_0);"
  if body.count(rec) != 1:
    raise SystemExit(f"WARN: the concat recursive call site is {body.count(rec)}")
  body = body.replace(rec,
                      "globalThis.__SN(\"concat\");\n"
                      "    const _x_0 = $$String_concat(_t_0);\n"
                      "    const __t = performance.now();\n"
                      "    const __v = (_h_0 + _x_0);\n"
                      "    globalThis.__SM(\"concat\", __t);\n"
                      "    return __v;")
  src = src[:i] + body + src[end:]

  # **AND THE **`join` **CLOCK**, **INSIDE **`join_go`'s **BODY** -- **AT **THE **RECURSIVE
  # **CALL's **SITE**, **AND **THE **CLOCK **SPANS **THE **REST **OF **THE **BODY**.
  #
  # **SO THE **`join` **CLOCK **IS **THE **`join_go` **CLOCK** -- **AND **THE **`join` **ENTRY
  # **COUNT **IS **AT **`$String_join`'s **BODY**.
  m = re.search(r"function (\$String_join)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_join")
  i, end = find_fn(src, "$String_join")
  body = src[i:end]
  call = "return $String_join_go(_t_0, _h_0, _sep_0);"
  if body.count(call) != 1:
    raise SystemExit(f"WARN: the join call site is {body.count(call)}")
  body = body.replace(call,
                      "globalThis.__SN(\"join\");\n"
                      "    const __t = performance.now();\n"
                      "    const __v = $String_join_go(_t_0, _h_0, _sep_0);\n"
                      "    globalThis.__SM(\"join\", __t);\n"
                      "    return __v;")
  src = src[:i] + body + src[end:]

  m = re.search(r"function (\$String_join_go)\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no $String_join_go")
  i, end = find_fn(src, "$String_join_go")
  body = src[i:end]
  rec = "const _x_0 = $$String_join_go(_t_0, _h2_0, _sep_0);"
  if body.count(rec) != 1:
    raise SystemExit(f"WARN: the join_go recursive call site is {body.count(rec)}")
  body = body.replace(rec,
                      "globalThis.__SN(\"joingo\");\n"
                      "    const _x_0 = $$String_join_go(_t_0, _h2_0, _sep_0);\n"
                      "    const __t = performance.now();\n"
                      "    const __v = ((_sep_0 + _x_0), (_h_0 + (_sep_0 + _x_0)));\n"
                      "    globalThis.__SM(\"joingo\", __t);\n"
                      "    return __v;")
  src = src[:i] + body + src[end:]

  # **THE **INDENT's **CLOCK**, **AT **ITS **ENTRY** -- **⇒⇒† AND **THE **ENTRY **IS **A **ONE-
  # **LINE **BODY** (⇒⇒† AND **THE **WHOLE **INDENT **IS **BUILT **IN **THE **`go` **CALL**), **⇒⇒†
  # **AND **AND **SO **THE **ENTRY's **CLOCK **SPANS **THE **`go` **CALL** (⇒⇒† AND **AND **THE
  # **`go` **BODY **IS **THE **WORK**)**.
  m = re.search(r"function (\$" + re.escape(INDENT) + r")\(([^)]*)\)\s*\{", src)
  if not m:
    raise SystemExit("WARN: no ku_indent")
  iname, iparams = m.group(1), m.group(2)
  i, end = find_fn(src, iname)
  ibody = src[i:end]
  # **⇒⇒† AND **THE **ENTRY **IS **THE **ONE **CALL **SITE **THAT **THE **COMPILED **FORM
  # **HAS **IN **ITS **BODY**, **⇒⇒† AND **AND **THE **OLD **BUILD **HAS **ONE **AND **THE **NEW
  # **BUILD **HAS **EIGHT** (⇒⇒† AND **THE **TABLE's **FALLBACK **PLUS **THE **SEVEN **LITERAL
  # **ARMS**) -- **⇒⇒† AND **AND **THE **INSTRUMENT **MUST **FIND **THE **ENTRY**, **⇒⇒† AND **AND
  # **THE **ENTRY **IS **THE **CALL **IN **THE **LAST **ARM** (⇒⇒† AND **AND **THE **ARMS **ARE **IN
  # **SOURCE **ORDER**)**.
  icall = f"return $_________tinybendygrad_renderer_cstyle_ku_indent_go((_depth_0 ), \"\");"
  # **⇒⇒† AND **THE **ENTRY **IS **CLOCKED **AT **ITS **OWN **BODY** (⇒⇒† AND **AND **THE **ENTRY
  # **MAY **HAVE **SEVERAL **CALL **SITES** (⇒⇒† AND **THE **NEW **BUILD's **TABLE **HAS **EIGHT**,
  # **⇒⇒† AND **AND **THE **OLD **BUILD **HAS **ONE**)), **⇒⇒† AND **AND **SO **THE **CLOCK **GOES
  # **AT **THE **ENTRY's **FIRST **STATEMENT** (⇒⇒† AND **AND **THE **ENTRY **IS **NOT
  # **RECURSIVE**, **⇒⇒† AND **AND **THE **ENTRY's **CLOCK **SPANS **THE **WHOLE **INDENT**)**
  if ibody.count(icall) == 0:
    raise SystemExit("WARN: the indent has no fallback call site")
  ibody = ibody.replace(icall,
                        "globalThis.__SN(\"indent\");\n"
                        "    const __t = performance.now();\n"
                        "    const __v = $_________tinybendygrad_renderer_cstyle_ku_indent_go((_depth_0 ), \"\");\n"
                        "    globalThis.__SM(\"indent\", __t);\n"
                        "    return __v;")
  src = src[:i] + ibody + src[end:]

  # **THE ACCUMULATOR**, AT THE TOP OF `$serve`.
  old = "globalThis.__S = globalThis.__S || {};"
  if src.count(old) != 0:
    raise SystemExit(f"WARN: the accumulator is already there ({src.count(old)})")
  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  # **AND THE RENDER's OWN WALL**, AT THE SAME SITE -- SO THE INSTRUMENT's OWN COST IS
  # MEASURED ON THE SAME CLOCK THE A/B USES.
  wall_old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  wall_new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  i = src.index(wall_old)
  src = src[:i] + wall_new + src[i + len(wall_old):]

  # **THE DUMP**, AT THE `@@END`.
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__S.n = (globalThis.__S.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".s",
        JSON.stringify({S: globalThis.__S || {}, W: globalThis.__W || []})); } catch (e) {} }
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
  out = BUILD / f"serve_text_{base.stem}.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, f"text{base.stem}")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  time.sleep(0.3)
  d.stop()

  import json
  # **THE DUMP **IS **AT **`__T_OUT` **+ **".s"** -- **AND **`__T_OUT` **IS **THE **DAEMON's OWN
  # **FILE**, **SO **THE **PATH **IS **READ **FROM **THE **DAEMON** AND **NOT **GUESSED**.
  dump = pathlib.Path(str(d.cpu_file) + ".s")
  data = json.loads(dump.read_text())
  S = data.get("S", {})
  W = [w["w"] for w in data.get("W", [])]
  n = S.get("n", 1) or 1
  print()
  print("THE **RENDER's **STRING **WORK**, **IN THE DAEMON** (60 turns), ms a turn:")
  print(f"  concat        {S.get('concat', 0)/n:.4f}   (the CONCAT's OWN work, the TAIL's)")
  print(f"  join          {S.get('join', 0)/n:.4f}   (the WHOLE join, the ENTRY's clock)")
  print(f"  joingo        {S.get('joingo', 0)/n:.4f}   (**NESTED **IN **`join`**) -- **AND **THIS **IS")
  print( "                **THE **LIST **WALK's **COST**, **WHICH **IS **THE **AMPLIFICATION **FACTOR**)")
  print()
  print(f"  indent        {S.get('indent', 0)/n:.4f}   (the INDENT's OWN work)")
  print(f"  indent CALLS a turn: {S.get('indent.n', 0)/n:.1f}")
  print(f"  concat CALLS a turn: {S.get('concat.n', 0)/n:.1f}")
  print(f"  join   CALLS a turn: {S.get('join.n', 0)/n:.1f}")
  print(f"  joingo CALLS a turn: {S.get('joingo.n', 0)/n:.1f}   (**THE **PIECES **WALKED**)")
  if W:
    W.sort()
    print()
    print("AND **THE **INSTRUMENT's OWN COST**, FROM **THE SAME DUMP**:")
    print(f"  THE RENDER's WALL **IN THE SHAPED BUILD**: min {min(W):.4f}  median {W[len(W)//2]:.4f}")
  print()
  print("**AND THE **COUNTS **ARE **THE **MULTIPLIERS** (§138's LESSON: **THE COUNT IS NOT THE")
  print("**COST**, **BUT **THE COUNT MULTIPLIES **THE **COST**) -- **AND **THE **`joingo` **COUNT **IS")
  print("**THE **LIST **WALK's **LENGTH**, **WHICH **IS **THE **AMPLIFICATION **FACTOR**.**")


if __name__ == "__main__":
  main()
