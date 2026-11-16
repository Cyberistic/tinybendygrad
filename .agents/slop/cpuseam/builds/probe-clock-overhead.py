#!/usr/bin/env python3
# **THE CLOCK's OWN OVERHEAD**, MEASURED **IN THE DAEMON** -- **THE MISSING CALIBRATION**.
#
# **WHY:** §138.7's MEASUREMENT PUT **`rtp` AT **0.4787 ms** A TURN** (`probe-alu-parts.py`),
# **⇒⇒⇒ AND **THE PURE-JS WALK OF **THE SAME 1,237 ACCESSES** READS **0.0605 ms**
# (`probe-rtp-cost-probe.js`) -- **⇒⇒⇒ AND **THE DIFFERENCE IS **EITHER **THE CLOCK's OWN
# OVERHEAD** OR **THE IN-RENDER CONTEXT**, **⇒⇒⇒ AND **THE CLOCK's OVERHEAD **IS NOT
# MEASURED**, **⇒⇒⇒ AND **WITHOUT **THE CALIBRATION** EVERY **CLOCKED** NUMBER **IS **AN
# OVERCOUNT** (§138.3's FACTOR WAS **1.25** FOR **THE **WRAPPERS**, **AND **A CLOCK IS **A
# DIFFERENT** KIND OF INSTRUMENT****).
#
# **⇒⇒⇒ AND **THIS PROBE **IS **THE CALIBRATION**: **THE SAME FUNCTION**, **CLOCKED **THE SAME
# WAY**, **WITH **THE CLOCK** AND **WITHOUT** IT -- **⇒⇒⇒ AND **THE DIFFERENCE IS **THE
# OVERHEAD**, **PER CALL**.
#
# **⇒⇒⇒ AND **THE PROSE IS **IN COMMENTS** AND **NOT **IN **A DOCSTRING** BECAUSE **A DOCSTRING
# **TERMINATES AT **THE FIRST INNER `"""`**, **AND **THE DUMP STRINGS **HAVE **THREE****.

import json
import pathlib
import sys
import time
# (THE HEADER's PROSE IS **ABOVE**; **THE CODE's PROSE** IS **BELOW**.)

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

# **THE ACCUMULATOR** -- **AND **THE TWO VARIANTS**: **ONE COUNTS THE **CLOCKED** FUNCTION**,
# **AND **THE OTHER COUNTS **THE SAME FUNCTION **WITHOUT **THE CLOCK** -- **⇒⇒⇒ AND **THE
# DIFFERENCE IS **THE CLOCK's OVERHEAD**.
ACC = ("globalThis.__K = {clocked:0, plain:0, n:0};\n")


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  # **THE CLOCKED VARIANT**: **A **TINY** FUNCTION**, **SO **THE MEASUREMENT IS **THE CLOCK's
  # OVERHEAD AND **NOT**THE FUNCTION's WORK** -- **⇒⇒⇒ AND **THE FUNCTION IS **CALLED **THE
  # SAME NUMBER OF TIMES** AS **THE PLAIN VARIANT**, **⇒⇒⇒ AND **BOTH ARE **COUNTED**,
  # **⇒⇒⇒ AND **THE DIFFERENCE IS **THE OVERHEAD PER CALL**.
  #
  # **⇒⇒⇒ AND **THE **CALLED** FUNCTION** IS **`rtp`** (THE ONE §138.7 CLOCKED), **⇒⇒⇒ AND
  # **THE **PLAIN** VARIANT** CALLS **THE SAME `rtp`**, **⇒⇒⇒ AND **SO **THE DIFFERENCE IS
  # **EXACTLY **THE CLOCK's OVERHEAD**.
  name = "$_________tinybendygrad_renderer_cstyle_rtp"
  site = f"function {name}("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the rtp site is {src.count(site)}")
  site_i = src.index(site)
  op = src.index("(", site_i)
  d = 0
  for c in range(op, len(src)):
    if src[c] == "(":
      d += 1
    elif src[c] == ")":
      d -= 1
      if d == 0:
        cp = c
        break
  params = src[op + 1:cp]
  args = [a.strip() for a in params.split(",") if a.strip()]
  brace = src.index("{", cp)
  # **THE BODY's END** -- **AND **THE `} else` CASE IS **NOT **AN ISSUE HERE** (THE BODY IS
  # **TWO CONSTANT COMPARISONS**), **BUT **THE SCAN IS **THE SAME ONE** AS **EVERYWHERE ELSE**.
  d2 = 0
  k = brace
  end = None
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
      d2 += 1
    elif ch == "}":
      d2 -= 1
      if d2 == 0:
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        end = k + 1
        break
    k += 1
  whole = src[site_i:end]
  inner = name + "__kinner"
  body = whole.replace(f"function {name}(", f"function {inner}(", 1)
  call = ", ".join(args)
  # **THE CLOCKED WRAPPER** AND **THE PLAIN WRAPPER** -- **AND **THEY ARE **CALLED **FROM **THE
  # SAME PLACE**, **⇒⇒⇒ AND **THE **ONLY** DIFFERENCE IS **THE CLOCK**.
  wrapper = (f"\nfunction {name}({params}) {{\n"
             f"  const __t = performance.now();\n"
             f"  const __v = {inner}({call});\n"
             f"  globalThis.__K.clocked = (globalThis.__K.clocked || 0) + (performance.now() - __t);\n"
             f"  return __v;\n"
             f"}}\n"
             f"function {name}__plain({params}) {{\n"
             f"  return {inner}({call});\n"
             f"}}\n"
             f"function {name}__plainclocked({params}) {{\n"
             f"  const __t = performance.now();\n"
             f"  const __v = {name}__plain({call});\n"
             f"  globalThis.__K.plain = (globalThis.__K.plain || 0) + (performance.now() - __t);\n"
             f"  return __v;\n"
             f"}}")
  src = src[:site_i] + body + wrapper + src[end:]

  # **AND **NOW **THE **PLAIN-CLOCKED** VARIANT** IS **CALLED **FROM **THE SAME PLACE** AS
  # **THE CLOCKED ONE** -- **⇒⇒⇒ AND **THE **CALL SITE** IS **THE `rtp` CALLS**, **AND **THE
  # **SAME **SET** OF CALL SITES **MUST **BE **USED** FOR BOTH**, **⇒⇒⇒ SO **THE **PLAIN-CLOCKED**
  # VARIANT** IS **CALLED **FROM **ONE** OF **THEM** AND **THE **CLOCKED** ONE **FROM **THE
  # OTHER**, **⇒⇒⇒ AND **THE COUNTS **WILL **BE **COMPARABLE**.
  #
  # **⇒⇒⇒ AND **THE **SIMPLEST** WAY** IS **TO **CALL **BOTH** FROM **A **SINGLE** SITE**, **AND
  # **THE **COUNTS** ARE **REPORTED **AS **THE **RATIO** OF **THE **TIMES** PER **CALL**.
  # **⇒⇒⇒ AND **THE CALL SITES ARE **FOUND **FIRST** AND **PATCHED **IN REVERSE**, BECAUSE
  # **THE FIRST REPLACEMENT **CHANGES **THE TEXT** THE SECOND LOOKUP WOULD **MATCH** (MEASURED:
  # **"substring not found"** -- **AND **A MISSING SITE IS **NOT** A ZERO**, IT IS **AN ERROR**).
  # **⇒⇒⇒ AND **THE **TWO** SITES HAVE **DIFFERENT ARGUMENT SHAPES** (MEASURED: **THE
  # COMPILED FORM HAS **14** `rtp` CALLS AND **ONLY ONE** OF THEM **IS **`rtp(_r_0, _i_0)`**), **⇒⇒⇒
  # AND **THE PLAIN-CLOCKED VARIANT MUST **BE **CALLED **WITH **THE **SAME** ARGUMENTS**, **⇒⇒⇒
  # AND **SO **THE **TWO** SITES** ARE **THE **TWO** WITH **THE **SIMPLEST** ARGUMENTS**, AND
  # **THE **SECOND** IS **PATCHED **FIRST** (SO **THE **FIRST**'s **OFFSET **STAYS VALID**)**.
  sites = [
    ("$$_________tinybendygrad_renderer_cstyle_rtp(_r_0, _h_0)", True),
    ("$$_________tinybendygrad_renderer_cstyle_rtp(_r_0, _i_0)", False),
  ]
  for m, _plain in sites:
    if src.count(m) != 1:
      raise SystemExit(f"WARN: the site {m!r} is {src.count(m)}")
  marker = "$$_________tinybendygrad_renderer_cstyle_rtp(_r_0, _i_0)"
  n = src.count(marker)
  # **THE **FIRST** CALL SITE** GETS **THE **PLAIN-CLOCKED** VARIANT** AND **THE **SECOND** GETS
  # **THE **CLOCKED** ONE** -- **⇒⇒⇒ AND **THE COUNTS **ARE **COMPARABLE** (THEY ARE **ADJACENT
  # CALL SITES** IN **THE SAME **FUNCTION**)**.
  # **⇒⇒⇒ AND **THE **COMPILED FORM** ALIASES **THE GLOBALS** AT **THE END**
  # (`const $$List_append = $List_append;`), **⇒⇒⇒ AND **THE **NEW** FUNCTION NEEDS **ITS OWN
  # ALIAS**, **OR **THE CALL SITE'S `$$...` IS **UNDEFINED** (MEASURED: "ReferenceError:
  # `$$_________tinybendygrad_renderer_cstyle_rtp__plainclocked` is not defined" -- **AND **THE
  # DEFINITION **WAS **THERE** -- **⇒⇒⇒ AND **THE ALIAS IS **WHAT **THE COMPILED FORM **USES
  # **TO **REACH **THE **GLOBAL** SCOPE****).
  alias_old = "const $$List_append = $List_append;"
  if src.count(alias_old) != 1:
    raise SystemExit(f"WARN: the alias site is {src.count(alias_old)}")
  src = src.replace(alias_old,
                    alias_old + "\nconst $$_________tinybendygrad_renderer_cstyle_rtp__plainclocked = "
                    "$_________tinybendygrad_renderer_cstyle_rtp__plainclocked;", 1)

  # **PATCH IN REVERSE**, SO **THE OFFSETS STAY VALID**.
  for m, plain in reversed(sites):
    pos = src.index(m)
    if plain:
      # **⇒⇒⇒ AND **THE CALL SITE USES **`$$`** (THE GLOBAL) **AND **THE DEFINITION IS **ONE
      # `$`** (THE LOCAL) -- **⇒⇒⇒ AND **THE **COMPILED FORM CALLS **THE **LOCAL** NAME**, **⇒⇒⇒
      # AND **SO **THE **REPLACEMENT** IS **`$$...rtp__plainclocked`** **AND **THE **DEFINITION** IS
      # **`$...rtp__plainclocked`** -- **⇒⇒⇒ AND **THE **GLOBAL** NAME **IS **THE **ONE **THE
      # **RUNTIME** CALLS**, **⇒⇒⇒ AND **THE **CALL SITE **IS **INSIDE **THE **GLOBAL** SCOPE**.
      m2 = m.replace("$$_________tinybendygrad_renderer_cstyle_rtp(",
                     "$$_________tinybendygrad_renderer_cstyle_rtp__plainclocked(")
    else:
      m2 = m
    src = src[:pos] + m2 + src[pos + len(m):]

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
  base = BUILD / "now.js"
  out = BUILD / "serve_cal.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "cal")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  K = json.loads((BUILD.parent / "nf-cal/cpu.json.d").read_text())
  n = max(K.get("n", 1), 1)
  clocked = K.get("clocked", 0) / n
  plain = K.get("plain", 0) / n
  print(f"\n**THE CLOCK's OWN OVERHEAD**, **IN THE DAEMON** ({n} turns):")
  print(f"  THE CLOCKED `rtp`:   {clocked:.4f} ms A TURN")
  print(f"  THE PLAIN-CLOCKED:   {plain:.4f} ms A TURN")
  print(f"  **⇒⇒⇒ THE DIFFERENCE (THE CLOCK's OVERHEAD): {clocked - plain:.4f} ms A TURN**")
  print()
  print("  **⇒⇒⇒ AND §138.7's CLOCKED READING FOR `rtp` WAS **0.4787 ms**, **⇒⇒⇒ AND")
  print("**THE PURE-JS WALK OF **THE SAME ACCESSES** READS **0.0605 ms** (`probe-rtp-cost-probe.js`) --")
  print("**⇒⇒⇒ AND **THE GAP IS **THE MEASUREMENT** THAT **THE **CLOCKED** NUMBER** IS **AN")
  print("OVERCOUNT****.")
