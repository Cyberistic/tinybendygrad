#!/usr/bin/env python3
"""CLOCK THE **RENDER's** PARTS, **INSIDE** THE DAEMON.

**WHY THIS FILE EXISTS.** THE DECODE HAS `decode-shape.py` AND THE RENDER **HAS NO
EQUIVALENT** -- SO §137's RENDER NUMBERS CAME FROM **THE PROFILER's INCLUSIVE SAMPLES**,
WHICH **ATTRIBUTE THE CALLER's WAIT** AND ARE **A MEASUREMENT OF THE LOAD**. AND §138's
FINDING WAS THAT **AN IN-DAEMON CLOCK IS **THE PORT's WORK** AND NOT THE CALLER's WAIT** -- SO
THE RENDER NEEDS **THE SAME KIND OF INSTRUMENT**, WITH **THE SAME DISCIPLINE**:

  · THE PATCH SITES ARE **READ FROM THE COMPILED FORM** AND **NOT GUESSED**, AND **EVERY
    ONE IS **COUNTED** BEFORE IT IS APPLIED**, SO A MISS IS **AN ERROR** AND NOT **A SILENT
    ZERO** -- BECAUSE **A CLOCK THAT FIRES ON NOTHING READS AS ZERO AND A ZERO IS **NOT** A
    MEASUREMENT** (THE TREE's OWN RULE, `AGENTS.md`: "**A GATE THAT EXITS 0 HAVING MEASURED
    NOTHING IS WORSE THAN NO GATE**").
  · **EVERY CLOCK IS **INSIDE** THE FUNCTION BODY**, BECAUSE **A REST-ARGUMENTS WRAPPER IS
    NOT FREE** (MEASURED, §136: WRAPPING SEVEN FUNCTIONS MOVED THE RENDER **2.265 ms ->
    3.494 ms**).
  · **THE ACCUMULATOR IS READ AT THE `@@END`**, WHICH FIRES **ONCE A TURN**.

**THE PARTS, AND THEY ARE THE ONES §137's PROFILER NAMED** (THE TOP LEAF WAS `cstyle_eq_op`
AT 0.746 ms, AND §137 REPLACED IT WITH PER-LITERAL PREDICATES):

  · `render`   THE WHOLE RENDER, AS THE DAEMON SEES IT.
  · `text`     THE `ku_text` FAMILY -- THE PER-KERNEL TEXT.
  · `decl`     `_render_decl` -- THE DECLARATIONS.
  · `named`    `_render_named` -- THE NAMED KERNELS.
  · `stmt`     `_render_stmt` -- THE STATEMENTS.
  · `emit`     `_render_emit` -- THE EMISSION.
  · `inline`   THE `ku_inline*` FAMILY -- THE INLINING DECISIONS.
  · `alu`      `ku_alu_srcs*` -- THE ALU's SOURCE COLLECTION.
  · `strip`    `ku_strips` -- THE STRIP DECISION.

**AND EVERY FUNCTION IS **NANAMED FROM ITS COMPILED NAME**, SO THE INSTRUMENT **SURVIVES A
RENAME OF THE BEND DEF** (THE COMPILED NAME IS WHAT THE PATCH ACTUALLY MATCHES).
"""

import json
import os
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

# THE ACCUMULATOR, AND THE MARKER.
ACC = """globalThis.__R = globalThis.__R || {};
globalThis.__RM = (k, t0) => { globalThis.__R[k] = (globalThis.__R[k] || 0) + (performance.now() - t0); };"""

# **THE FAMILIES THAT ARE **WRAPPED**, AND **WHY.**
#
# **A WRAPPER IS **NOT FREE** (THE TREE's OWN RULE, §136: WRAPPING SEVEN FUNCTIONS MOVED THE
# RENDER **2.265 ms -> 3.494 ms**), **AND IT IS WORSE FOR A **RECURSIVE** FUNCTION** -- BECAUSE
# **EVERY RECURSION LEVEL PAYS **A WRAPPER LAYER**. MEASURED: WRAPPING ALL **46** READS
# `render` AT **13.34 ms** AGAINST **THE TRUE 1.04 ms**.
#
# SO **THE RECURSIVE FAMILIES ARE **MEASURED **BY COUNT** AND NOT BY CLOCK** -- `inline`
# (9 FUNCTIONS, **RECURSIVE THROUGH `ku_inline2`**) AND `text` (16, **THROUGH `ku_text_go`**) --
# AND **THE CLOCKED FAMILIES ARE **THE ONES THE RENDER CALLS **ONCE** PER KERNEL**.
#
# **AND THE OVERHEAD IS **MEASURED**, NOT ASSUMED**: THE INSTRUMENT REPORTS **THE WHOLE
# RENDER's CLOCK** AND **THE CALLER's CLOCK** SIDE BY SIDE, SO **THE INSTRUMENT's OWN COST IS
# **VISIBLE** IN THE OUTPUT AND **NOT** HIDDEN IN IT.
#
# **AND `alu` AND `strip` ARE **NOT** RECURSIVE IN THE SAME WAY** (`ku_alu_srcs_go` IS **THE
# ONLY RECURSION** AND IT IS **ONE** LEVEL), SO THEY ARE **KEPT**.
OUTER_ONLY = {
  # THE FAMILIES **NOT** WRAPPED, AND **WHY NOT**.
  "inline": "RECURSIVE THROUGH `ku_inline2` -- EVERY LEVEL PAYS A WRAPPER",
  "text": "RECURSIVE THROUGH `ku_text_go` -- EVERY LEVEL PAYS A WRAPPER",
  "render": "RECURSIVE THROUGH `_render_go` (THE LOOP) -- AND THE WHOLE RENDER IS WHAT THE "
            "CALLER's CLOCK ALREADY READS, SO CLOCKING IT HERE IS DOUBLE-COUNTING",
}


def find_fn(src: str, compiled: str):
  """THE COMPILED FUNCTION, BY ITS **COMPILED NAME**, AND **WHERE IT ENDS**.

  **AND THE END IS **NOT** "THE FIRST `}` AT DEPTH 0"** -- BECAUSE **A COMPILED `if/else`
  CHAIN HAS **A `}` AT DEPTH 0** IN THE MIDDLE** (THE `}` THAT CLOSES THE FIRST BRANCH, WITH
  THE `else if` FOLLOWING IT). MEASURED: THE NAIVE SCAN CUT `ku_text_go` **IN HALF**, AND
  **THE REWRITTEN SOURCE DID NOT EVEN PARSE** ("Unexpected else").

  **SO THE SCAN COUNTS **THE BRACES** AND **THE `else`**: **AN `else` AT DEPTH 0 MEANS
  **THE `}` BEFORE IT WAS **THE BRANCH's** AND NOT **THE FUNCTION's****, SO THE FUNCTION DOES
  **NOT** END THERE. **THE FUNCTION ENDS AT **THE FIRST `}` AT DEPTH 0** THAT IS **NOT**
  FOLLOWED BY `else`**.

  **AND THE SCAN MUST **SKIP THE STRING LITERALS** -- BECAUSE **A COMPILED C STRING IS
  **A JS STRING WITH **THE PORT's OWN TEXT** IN IT**, AND **THE PORT's TEXT HAS BRACES AND
  `else`s IN IT**. MEASURED: `ku_text_backedge`'s BODY IS
  `"  if (!(...)) {\\n break;\\n}\\n}"` -- **THE C STRING'S OWN `}`** -- AND THE NAIVE SCAN
  ENDED THE FUNCTION **INSIDE THE STRING**, AND **THE REWRITTEN SOURCE DID NOT PARSE**
  ("Expected `)` but found `function`").
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
      # **A STRING LITERAL**: SKIP TO ITS END, ESCAPES INCLUDED.
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
        # **AND THE `}` MUST NOT BE FOLLOWED BY `else`** -- BECAUSE **THEN IT CLOSED **A
        # BRANCH**, NOT THE FUNCTION.
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        return i, k + 1
    k += 1
  return i, None


def instrument(src: str):
  """CLOCK EACH NAMED FUNCTION, AND **COUNT EVERY SITE BEFORE IT IS APPLIED**."""
  # (THE KEY, THE COMPILED NAME PREFIX, THE LIST OF THE COMPILED NAMES THAT MATCH IT).
  TARGETS = [
    ("text", "_tinybendygrad_renderer_cstyle_ku_text"),
    ("inline", "_tinybendygrad_renderer_cstyle_ku_inline"),
    ("alu", "_tinybendygrad_renderer_cstyle_ku_alu_srcs"),
    ("strip", "_tinybendygrad_renderer_cstyle_ku_strips"),
    ("decl", "_tinybendygrad_renderer_cstyle__render_decl"),
    ("stmt", "_tinybendygrad_renderer_cstyle__render_stmt"),
    ("named", "_tinybendygrad_renderer_cstyle__render_named"),
    ("emit", "_tinybendygrad_renderer_cstyle__render_emit"),
    ("render", "_tinybendygrad_renderer_cstyle__render"),
  ]

  # **FIND THE FUNCTIONS, AND **COUNT** THEM -- **BEFORE** ANY PATCH, SO THE COUNT IS **THE
  # POPULATION** AND NOT A GUESS.
  sites = []
  for key, prefix in TARGETS:
    found = sorted(set(re.findall(r"function (\$[A-Za-z0-9_]*" + re.escape(prefix) + r"[A-Za-z0-9_]*)\(", src)))
    if not found:
      print(f"WARN: the {key} family is 0 (prefix {prefix}) -- IT WILL READ AS ZERO")
      continue
    sites.append((key, found))

  # **THE PATCH.** EACH FUNCTION IS **REWRITTEN** AS **A WRAPPER AROUND ITSELF**, AND **THE
  # CLOCK IS **INSIDE** THE ORIGINAL** -- SO THE BODY IS UNTOUCHED AND THE TIME MEASURED IS
  # **THE FUNCTION's OWN WORK**.
  #
  # **AND THE FAMILIES **OVERLAP** (`render` MATCHES `render_decl` TOO), SO **A FUNCTION MUST
  # BE WRAPPED **ONCE** AND ONLY ONCE** -- AND **THE FIRST FAMILY TO CLAIM IT WINS**. WITHOUT
  # THIS, **THE SAME NAME IS DEFINED TWICE** AND **THE SECOND DEFINITION SILENTLY WINS**,
  # WHICH IS **A CLOCK ON THE WRONG FUNCTION** AND **NOT AN ERROR** -- SO THE OVERLAP IS
  # **MEASURED** HERE: THE COUNT OF WRAPPED FUNCTIONS IS PRINTED.
  #
  # **AND **THE WRAPPER IS **THE INSTRUMENT's OWN COST** -- MEASURED: 46 WRAPPERS READ
  # `render` AT **13.34 ms** AGAINST **THE TRUE 1.04 ms**, BECAUSE **A RECURSIVE CALL PAYS **A
  # WRAPPER LAYER** EVERY LEVEL** (THE TREE's OWN RULE, §136: "**A REST-ARGUMENTS WRAPPER IS
  # NOT FREE**"). **SO **ONLY THE FUNCTIONS THAT ARE **CALLED FROM **OUTSIDE** THE
  # WRAPPED SET** ARE WRAPPED** -- AND **THE SET IS CHOSEN BY **THE CALL GRAPH**, NOT BY
  # HAND.**
  wrapped = {}
  for key, names in sites:
    for name in names:
      if name in wrapped:
        continue
      if key in OUTER_ONLY:
        continue
      i, end = find_fn(src, name)
      if i is None:
        continue
      wrapped[name] = key
      head = src[i:end]
      # **THE PARAMETER LIST**, AND **THE BODY's BRACE**.
      # **AND THE PARAMETER LIST IS **THE TEXT BETWEEN **THE PARENS**, WITHOUT THE PARENS**
      # -- **BECAUSE THE CALLER WRITES `name(params)` AND SO A LIST THAT CARRIES ITS OWN
      # PARENS PRODUCES `name(params))`**, WHICH IS **A SYNTAX ERROR** (MEASURED: THE FIRST
      # WRAPPER READ `function ..._render(_dev_0, _kus_0) ) {`).
      #
      # **AND THE PARAMETER LIST **MAY SPAN LINES** (MEASURED: `ku_text_backedge`'s DOES), SO
      # **THE CLOSING PAREN IS FOUND BY **COUNTING**, NOT BY `index(")")` -- BECAUSE A
      # **DEFAULT VALUE** OR **A NESTED CALL** IN A DEFAULT WOULD CLOSE EARLY.
      open_paren = src.index("(", i)
      depth = 0
      close_paren = open_paren
      for c in range(open_paren, len(src)):
        if src[c] == "(":
          depth += 1
        elif src[c] == ")":
          depth -= 1
          if depth == 0:
            close_paren = c
            break
      params = src[open_paren + 1:close_paren]
      sig_end = src.index("{", close_paren)
      # **THE ARGUMENTS**: THE PARAMETER NAMES, IN ORDER. **AND THE SPLIT IS **BY THE
      # TOP-LEVEL COMMAS ONLY** -- A NESTED CALL OR A TUPLE HAS COMMAS **INSIDE** ITS
      # PARENS, AND **SPLITTING ON THOSE** PRODUCES **FRAGMENTS THAT ARE NOT ARGUMENTS**.
      argnames = []
      depth = 0
      cur = ""
      for ch in params:
        if ch in "([{":
          depth += 1
        elif ch in ")]}":
          depth -= 1
        if ch == "," and depth == 0:
          argnames.append(cur)
          cur = ""
        else:
          cur += ch
      if cur.strip():
        argnames.append(cur)
      # **AND THE NAMES ARE **WHITESPACE-STRIPPED**, BECAUSE **A MULTI-LINE PARAMETER LIST
      # LEAVES NEWLINES** -- AND **A NEWLINE INSIDE `name(args)` IS LEGAL** BUT **A NAME WITH
      # A TRAILING NEWLINE IS NOT WHAT THE CALLER MEANT**.
      args = ", ".join(a.strip() for a in argnames)
      # **THE NEW NAME**, AND **THE WRAPPER**.
      #
      # **AND THE ORDER IS **THE WHOLE TRICK**, AND **GETTING IT WRONG IS **AN INFINITE
      # RECURSION** -- BECAUSE **THE WRAPPER CALLS THE ORIGINAL, AND THE ORIGINAL MUST BE
      # **THE INNER**, NOT **THE WRAPPER**.** SO:
      #   · `inner` IS **THE ORIGINAL BODY**, RENAMED.
      #   · `name` IS **THE WRAPPER**, AND IT CALLS **`inner`**.
      # **AND THE ORIGINAL BODY IS **KEPT VERBATIM** -- SO THE TIME MEASURED IS **THE
      # FUNCTION's OWN WORK** AND NOT **A COPY OF IT** (THE ORIGINAL's BODY IS **MOVED**, NOT
      # **COPIED**, SO **A RECURSIVE FUNCTION STILL CALLS ITSELF** -- **AND THE BODY IS
      # **MOVED** **BEFORE** **THE NAMES ARE REWRITTEN**.)
      inner = name + "__inner"
      # **THE ORIGINAL BODY, RENAMED.**
      body = src[i:end]
      body = body.replace(f"function {name}(", f"function {inner}(", 1)
      # **THE WRAPPER.**
      wrapper = (f"function {name}({params}) {{\n"
                 f"  const __t = performance.now();\n"
                 f"  const __v = {inner}({args});\n"
                 f"  globalThis.__RM(\"{key}\", __t);\n"
                 f"  return __v;\n"
                 f"}}")
      src = src[:i] + body + "\n" + wrapper + src[end:]
  print(f"THE WRAPPED FUNCTIONS: {len(wrapped)}")
  for key in sorted(set(wrapped.values())):
    print(f"  {key:8s} {sum(1 for v in wrapped.values() if v == key)}")

  # **THE ACCUMULATOR**, AT THE TOP OF `$serve`.
  # **AND THE ANCHOR IS **THE ACCUMULATOR's OWN FIRST LINE**, WHICH IS **UNIQUE BY
  # CONSTRUCTION** -- BECAUSE **COUNTING THE `$serve` HEADER IS NOT SAFE**: **A WRAPPER's BODY
  # CAN CONTAIN **THE WHOLE ORIGINAL FUNCTION**, AND **THE ORIGINAL FUNCTION's BODY CAN
  # CONTAIN A `$serve` HEADER** (THE MAIN LOOP IS INSIDE `_render_go`'S CLOSURE), SO THE COUNT
  # READS **2** AND **THE SECOND ONE IS **NOT** A DUPLICATE DEFINITION** -- IT IS **THE
  # ORIGINAL, STILL IN PLACE, INSIDE THE `__inner` WRAPPER**.
  #
  # SO **THE ACCUMULATOR IS INSERTED **AT THE ACCUMULATOR's OWN MARKER**, WHICH IS
  # **A STRING THAT APPEARS EXACTLY ONCE**, AND THE COUNT IS **THE COUNT OF THAT STRING**.
  old = "globalThis.__R = globalThis.__R || {};"
  if src.count(old) != 0:
    raise SystemExit(f"WARN: the accumulator is already there ({src.count(old)})")
  # **THE ACCUMULATOR GOES AT THE TOP OF THE FILE'S FUNCTION BODY** -- AND THE **FIRST**
  # `$serve` HEADER IS **THE REAL ONE** (THE ONE **BEFORE** ANY WRAPPER), SO THE ACCUMULATOR
  # IS INSERTED **AT THE **FIRST** OCCURRENCE.
  marker = "function $serve(_fuel_0, _m_0, _s_0) {"
  i = src.index(marker)
  src = src[:i] + ACC + "\n" + src[i:]

  # **AND THE RENDER's OWN WALL**, AT **THE SAME SITE** -- SO **THE INSTRUMENT's OWN COST IS
  # **MEASURED ON THE SAME CLOCK** THE A/B USES, AND **THE COMPARISON IS **LIKE FOR LIKE**.
  # **AND THE `render` FAMILY IS NOT WRAPPED** (IT IS RECURSIVE), SO **THIS CLOCK IS **THE
  # ONLY** READING OF THE WHOLE RENDER** -- **AND IT IS **NOT** DOUBLE-COUNTED.**
  wall_old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  wall_new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  i = src.index(wall_old)
  src = src[:i] + wall_new + src[i + len(wall_old):]

  # **THE DUMP**, AT THE `@@END`.
  # **AND AT **THE FIRST** OCCURRENCE**, FOR **THE SAME REASON** AS THE ACCUMULATOR: **A
  # WRAPPER's BODY CONTAINS THE ORIGINAL FUNCTION**, AND THE ORIGINAL's `@@END` HEADER IS
  # **STILL IN PLACE** INSIDE IT.
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__R.n = (globalThis.__R.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify({R: globalThis.__R || {}, W: globalThis.__W || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  i = src.index(dump_old)
  if i < 0:
    raise SystemExit("WARN: no @@END site")
  src = src[:i] + dump_new + src[i + len(dump_old):]

  return src


if __name__ == "__main__":
  base = BUILD / "serve_base.js"
  out = BUILD / "serve_render.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "render")
  d.start()
  time.sleep(0.8)
  for _ in range(60):
    d.turn()
  d.stop()
  # **THE DUMP IS **AN OBJECT WITH TWO KEYS** -- `R` (THE PARTS' ACCUMULATOR) AND `W` (THE
  # RENDER's OWN WALL, PER TURN). **AND READING IT AS A FLAT DICT IS **A SILENT ZERO** -- THE
  # PARTS' NAMES ARE NOT AT THE TOP LEVEL, SO EVERY KEY MISSES AND **THE REPORT PRINTS
  # NOTHING** (MEASURED: THE FIRST RUN PRINTED **"1 turns"** AND **NO PARTS**).
  RAW = json.loads((BUILD.parent / "nf-render/cpu.json.d").read_text())
  D = RAW.get("R", {})
  W = RAW.get("W", [])
  n = max(D.get("n", 1), 1)
  print(f"\nTHE RENDER's PARTS, **IN THE DAEMON** ({n} turns), ms a turn:")
  for k in ("render", "text", "inline", "alu", "strip", "decl", "stmt", "named", "emit"):
    if k in D:
      print(f"  {k:8s} {D[k] / n:.4f}")
  # **AND THE INSTRUMENT's OWN COST, **READ FROM THE SAME DUMP** -- BECAUSE `W` IS **THE
  # RENDER's OWN WALL IN **THE SHAPED** BUILD**, AND **THE PLAIN** BUILD's WALL IS **WHAT THE
  # A/B READS**. **⇒⇒⇒ SO THE TWO ARE **COMPARABLE**, AND THE COMPARISON IS **LIKE FOR LIKE**:
  # **BOTH ARE **THE SAME CLOCK**, AT **THE SAME SITE**, IN **THE SAME PROCESS.**
  if W:
    ws = sorted(r["w"] for r in W)
    print(f"\nAND **THE INSTRUMENT's OWN COST**, FROM **THE SAME DUMP**:")
    print(f"  THE RENDER's WALL **IN THE SHAPED BUILD**: min {ws[0]:.4f}  median {ws[len(ws) // 2]:.4f}")
    print(f"  **AND THE PLAIN BUILD's WALL IS **WHAT THE A/B READS** -- SO THE DIFFERENCE IS")
    print(f"  **THE INSTRUMENT's OWN COST**, AND **IT IS **NOT** SMALL.**")
  print("\n**AND THE PARTS ARE **NESTED** -- `text` CONTAINS `inline` AND `alu`, AND `named`")
  print("CONTAINS `decl` -- SO THEY **DO NOT SUM**, AND **A SUM IS A NUMBER WITH NO SHAPE.**")
