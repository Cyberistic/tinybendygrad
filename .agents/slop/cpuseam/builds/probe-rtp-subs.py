#!/usr/bin/env python3
"""CLOCK **THE `rtp` ACCESS's FOUR SUB-CALLS**, **ONE AT A TIME**, **INSIDE** THE DAEMON**.

**WHY:** MEASURED: **`rtp` IS **0.4787 ms** A TURN** (`probe-alu-parts.py`) -- **THE LARGEST
SINGLE THING MEASURED IN THE RENDER** -- **⇒⇒⇒ AND **THE PURE-JS WALK OF **THE SAME 1,237
ACCESSES** READS **0.0603 ms** (`probe-rtp-cost-probe.js`) -- **⇒⇒⇒ AND **THE **CLOCK's OWN
OVERHEAD** IS **WITHIN NOISE** (MEASURED, `probe-clock-overhead.py`: **-0.0121 ms**) -- **⇒⇒⇒
AND **SO **THE GAP IS **THE IN-RENDER CONTEXT**, **NOT **THE CLOCK** AND **NOT **THE WALK**.

**⇒⇒⇒ AND `rtp` IS **A COMPOSITION OF **FOUR** CALLS** -- `Rows_n`, `Rows_bi`, `Rows_off` AND
`Rows_blk` -- **⇒⇒⇒ AND **THE QUESTION IS **WHICH OF **THE FOUR** IS **THE COST**, **⇒⇒⇒ AND
**THE ANSWER **CANNOT **BE **GUESSED** (§138.5) -- **SO **IT IS **MEASURED**."""

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

ACC = ("globalThis.__S = {rows_n:0, rows_bi:0, rows_off:0, rows_blk:0, list_get:0, n:0};\n"
       "globalThis.__SM = (k, t0) => { globalThis.__S[k] += (performance.now() - t0); };")

TARGETS = [
  ("rows_n", "$_________tinybendygrad_renderer_cstyle_Rows_n"),
  ("rows_bi", "$_________tinybendygrad_renderer_cstyle_Rows_bi"),
  ("rows_off", "$_________tinybendygrad_renderer_cstyle_Rows_off"),
  ("rows_blk", "$_________tinybendygrad_renderer_cstyle_Rows_blk"),
  ("list_get", "$List_get"),
]


def body_end(src: str, brace: int) -> int:
  d = 0
  k = brace
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
      d += 1
    elif ch == "}":
      d -= 1
      if d == 0:
        rest = src[k + 1:k + 12].lstrip()
        if rest.startswith("else"):
          k += 1
          continue
        return k + 1
    k += 1
  raise SystemExit("no end")


def instrument(src: str) -> str:
  for key, name in TARGETS:
    site = f"function {name}("
    n = src.count(site)
    if n != 1:
      raise SystemExit(f"WARN: the {key} site is {n} (want 1)")
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
    end = body_end(src, brace)
    whole = src[site_i:end]
    inner = name + "__sinner"
    body = whole.replace(f"function {name}(", f"function {inner}(", 1)
    call = ", ".join(args)
    wrapper = (f"\nfunction {name}({params}) {{\n"
               f"  const __t = performance.now();\n"
               f"  const __v = {inner}({call});\n"
               f"  globalThis.__SM(\"{key}\", __t);\n"
               f"  return __v;\n"
               f"}}")
    src = src[:site_i] + body + wrapper + src[end:]
    # **⇒⇒⇒ AND **THE **NEW** FUNCTION NEEDS **THE **GLOBAL** ALIAS** (`const $$X = $X;`),
    # **BECAUSE **THE **CALL SITES **USE **`$$X`** (MEASURED: **WITHOUT **THE **ALIAS**, **THE
    # DAEMON EXITS** WITH **"ReferenceError: `$$...` is not defined"****).
    # **⇒⇒⇒ AND **THE **ALIAS** IS **ONLY **ADDED **IF **IT **IS NOT **THERE**** (MEASURED:
    # **THE COMPILED FORM **ALREADY** HAS **`const $$List_get = $List_get;`**, **⇒⇒⇒ AND **THE
    # PROBE'S UNCONDITIONAL INSERT **DECLARED **IT **TWICE** AND **THE SOURCE DID NOT PARSE**).
    alias_new = f"const $$" + name[1:] + f" = {name};"
    if alias_new not in src:
      alias_old = "const $$List_append = $List_append;"
      if src.count(alias_old) != 1:
        raise SystemExit(f"WARN: the alias site is {src.count(alias_old)}")
      src = src.replace(alias_old, alias_old + "\n" + alias_new, 1)

  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__S.n = (globalThis.__S.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__S || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  out = BUILD / "serve_rtpsub.js"
  out.write_text(instrument(base.read_text()))
  d = noisefloor.Daemon(out, "rtpsub")
  d.start()
  time.sleep(0.8)
  for _ in range(40):
    d.turn()
  d.stop()
  S = json.loads((BUILD.parent / "nf-rtpsub/cpu.json.d").read_text())
  n = max(S.get("n", 1), 1)
  print(f"\nTHE `rtp` ACCESS's SUB-CALLS, **IN THE DAEMON** ({n} turns), ms a turn:")
  for key, _ in TARGETS:
    if key in S:
      print(f"  {key:10s} {S[key] / n:.4f}")
  print()
  print("**⇒⇒⇒ AND `rtp` READS **0.4787 ms** (`probe-alu-parts.py`), **⇒⇒⇒ AND **THE FOUR")
  print("SUB-CALLS ARE **NESTED** (`Rows_blk` IS **INSIDE `Rows_get`**, AND `Rows_bi`/`Rows_off` ARE")
  print("**CALLED **BY `Rows_get`**) -- **⇒⇒⇒ SO **THEY **DO NOT SUM** -- **⇒⇒⇒ AND **THE VERDICT IS")
  print("**THE **DEEPEST** ONE****.")
