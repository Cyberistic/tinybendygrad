#!/usr/bin/env python3
"""COUNT **EVERY `List.get` CALL** A TURN, **BY ITS CALL SITE**, **IN THE DAEMON**.

**WHY:** MEASURED: **`List.get` IS **0.6414 ms** A TURN** (`probe-rtp-subs.py`) -- **THE LARGEST
SINGLE CLOCKED THING IN **THE RENDER** -- **⇒⇒⇒ AND **IT IS **CALLED FROM **12** PLACES** IN
**THE COMPILED FORM**, **⇒⇒⇒ AND **THE QUESTION IS **WHICH **OF **THE 12** IS **THE COST** --
**⇒⇒⇒ AND §138.5's LESSON SAYS **THE COUNT IS **NOT **THE COST**, **⇒⇒⇒ BUT **THE COUNT IS
**THE MULTIPLIER**, AND **THE **MULTIPLIER **PER **SITE** IS **WHAT **TELLS **THE FIX's
TARGET****.

**⇒⇒⇒ AND **EVERY **CALL SITE** GETS **ITS OWN COUNTER**, **AND **THE COUNTER IS **AT **THE
`List.get` ENTRY** (THE **PRELUDE's**), **⇒⇒⇒ AND **THE **COUNTER IS **FREE** (AN INCREMENT)**."""

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

ACC = "globalThis.__L = {n:0};"


def instrument(src: str) -> str:
  old = "function $serve(_fuel_0, _m_0, _s_0) {"
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the $serve site is {src.count(old)}")
  src = src.replace(old, ACC + "\n" + old, 1)

  # **THE `List.get` DEFINITION**, AND **A COUNTER **AT **THE **RECURSION** -- **⇒⇒⇒ AND **THE
  # COUNTER IS **AT **THE **ENTRY**, WHICH **IS **ONCE **PER **CALL** (THE RECURSION **RE-ENTERS
  # **THE **SAME** FUNCTION**, **⇒⇒⇒ AND **SO **THE COUNTER COUNTS **THE **STEPS**, **WHICH IS
  # **WHAT **WE **WANT** -- **THE **TOTAL **ELEMENTS **WALKED**)**.
  site = "function $List_get("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the List_get site is {src.count(site)}")
  op = src.index("(", src.index(site))
  d = 0
  for c in range(op, len(src)):
    if src[c] == "(":
      d += 1
    elif src[c] == ")":
      d -= 1
      if d == 0:
        cp = c
        break
  brace = src.index("{", cp)
  src = src[:brace + 1] + "\n  globalThis.__L.steps = (globalThis.__L.steps || 0) + 1;" + src[brace + 1:]

  # **AND **THE **CALL SITES**: **EACH **CALL** TO **`$List_get`** GETS **A COUNTER**, **SO **THE
  # **PER-SITE** COUNT IS **KNOWN**.
  #
  # **⇒⇒⇒ AND **THE **SITES ARE **IDENTIFIED BY **THE **ENCLOSING FUNCTION**, **AND **THE
  # **ENCLOSING FUNCTION** IS **FOUND **BY **THE **CALL SITE's **TEXT****.
  sites = []
  for m in re.finditer(r"\$\$List_get\(", src):
    start = src.rfind("\nfunction ", 0, m.start())
    fname = src[start + 10:src.index("(", start)]
    sites.append((m.start(), fname))
  # **⇒⇒⇒ AND **THE **COMMA EXPRESSION** IS **PARENTHESIZED** AND **THE **CALL's **CLOSING
  # PAREN** IS **FOUND **FIRST** (BY COUNTING), BECAUSE **A BARE COMMA EXPRESSION **IN **AN
  # ARGUMENT POSITION** READS AS **TWO ARGUMENTS** (MEASURED: "Expected `)` but found `;`").
  # **⇒⇒⇒ AND **THE **OFFSETS** ARE **VALID** BECAUSE **THE PATCHES GO **IN REVERSE****.
  for i, (pos, fname) in reversed(list(enumerate(sites))):
    op = src.index("(", pos)
    d = 0
    for x in range(op, len(src)):
      if src[x] in "([{":
        d += 1
      elif src[x] in ")]}":
        d -= 1
        if d == 0:
          cp = x
          break
    call = src[pos:cp + 1]
    src = src[:pos] + f"((globalThis.__L.s{i} = (globalThis.__L.s{i} || 0) + 1, 0), {call})" + src[cp + 1:]

  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__L.n = (globalThis.__L.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__L || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  return src, sites


if __name__ == "__main__":
  base = BUILD / "now.js"
  raw = base.read_text()
  out_src, sites = instrument(raw)
  (BUILD / "serve_listsites.js").write_text(out_src)
  d = noisefloor.Daemon(BUILD / "serve_listsites.js", "listsites")
  d.start()
  time.sleep(0.8)
  for _ in range(30):
    d.turn()
  d.stop()
  L = json.loads((BUILD.parent / "nf-listsites/cpu.json.d").read_text())
  n = max(L.get("n", 1), 1)
  print(f"\nTHE `List.get` STEPS A TURN: {L.get('steps', 0) // n}")
  print(f"AND **THE **CALL SITES**, BY **HOW OFTEN** (of {len(sites)}):")
  rows = []
  for i, (pos, fname) in enumerate(sites):
    c = L.get(f"s{i}", 0) // n
    if c:
      rows.append((c, fname))
  rows.sort(reverse=True)
  for c, fname in rows:
    print(f"  {c:8d} calls  {fname[-50:]}")
