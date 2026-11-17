#!/usr/bin/env python3
"""THE **FLAT **ROW **SEQUENCE**, **FROM **TWO **BUILDS**, **DIFFED**.

**THE **DIRECT **COMPARATOR**: **THE **RENDER **READS **THE **ROWS **ROW **BY **ROW**, **⇒⇒⇒ AND
**SO **THE **SEQUENCE **IS **THE **RENDER's **INPUT**, **⇒⇒⇒ AND **A **DIFF **OF **THE **SEQUENCE**
**IS **A **DIFF **OF **THE **RENDER's **INPUT** -- **⇒⇒⇒ AND **IT **NAMES **THE **EXACT **ROW**
**WHERE **THE **TWO **DISAGREE**.

**THE **PROBE **IS **A **DUMP **AT **THE **`Rows_blk` **SITE**, **⇒⇒⇒ AND **`Rows_blk` **IS **THE
**ONE **PLACE **EVERY **ROW **LOOKUP **GOES **THROUGH** (THE **OUTER **WALK) -- **⇒⇒⇒ AND **SO
**THE **DUMP **IS **THE **ROWS **AS **THE **RENDER **SEES **THEM**.

**THE **PROBE **IS **NOT **A **TIMING **PROBE**: **IT **CHANGES **THE **WORK**, **⇒⇒⇒ AND **SO IT
**IS **NEVER **MIXED **INTO **A **VERDICT**.
"""

import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam')
sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')

DUMP = ('\n  { const __ls = []; let __x = _r_0.ts; '
        'while (__x && __x.$ === "Con") { const __rs = []; let __y = __x.head; '
        'while (__y && __y.$ === "Con") { const __ps = []; let __z = __y.head; '
        'while (__z && __z.$ === "Con") { __ps.push(__z.head); __z = __z.tail; } '
        '__rs.push(__ps); __y = __y.tail; } __ls.push(__rs); __x = __x.tail; } '
        'if (globalThis.__RG) { globalThis.__RG.rows = __ls; globalThis.__RG.n += 1; } }')


def instrument(js_path: pathlib.Path, out_path: pathlib.Path, tag: str) -> pathlib.Path:
  src = js_path.read_text()
  name = "$_________tinybendygrad_renderer_cstyle_Rows_blk"
  site = f"function {name}("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the Rows_blk site is {src.count(site)}")
  i = src.index(site)
  b = src.index("{", i)
  src = src[:b + 1] + DUMP + src[b + 1:]
  old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
  src = src.replace(old2, f"globalThis.__RG = {{rows: [], n: 0}};\n" + old2, 1)
  old3 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  new3 = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__RG || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(old3) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(old3)}")
  src = src.replace(old3, new3, 1)
  out_path.write_text(src)
  return out_path


def dump(js: pathlib.Path, tag: str):
  """**THE **FLAT **SEQUENCE **OF **ROWS**, **AND **THE **BLOCK **LENGTHS**."""
  out = B / f"rg_{tag}.js"
  instrument(js, out, tag)
  d = noisefloor.Daemon(out, f"rg{tag}")
  d.start()
  time.sleep(0.8)
  d.turn()
  d.stop()
  R = json.loads((B.parent / f"nf-rg{tag}/cpu.json.d").read_text())
  blocks = R.get("rows", [])
  lens = [len(b) for b in blocks]
  flat = []
  for b in blocks:
    for row in b:
      flat.append(row)
  return blocks, lens, flat


if __name__ == "__main__":
  a = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else B / "base_now.js"
  b = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else B / "fwd_now.js"
  _, la, fa = dump(a, "a")
  _, lb, fb = dump(b, "b")
  print(f"A {a.name}: {len(la)} blocks, lens {la[:6]}...{la[-3:]}, {len(fa)} rows")
  print(f"B {b.name}: {len(lb)} blocks, lens {lb[:6]}...{lb[-3:]}, {len(fb)} rows")
  print(f"A sum of lens = {sum(la)}, B sum = {sum(lb)}")
  # **THE **REVERSE **OR **NOT**: **THE **OLD **LAYOUT **IS **THE **NEWEST **FIRST**, **⇒⇒⇒ AND **THE
  # **NEW **ONE **IS **THE **OLDEST **FIRST** -- **⇒⇒⇒ AND **SO **THE **FLAT **SEQUENCE **MUST **BE
  # **REVERSED **BEFORE **THE **TWO **ARE **COMPARED** (THE **RENDER **READS **ROW **0 **FIRST**,
  # **AND **THE **ROW's **CONTENT **MUST **BE **THE **SAME **ROW**)**.
  ra = list(reversed(fa))
  n = min(len(ra), len(fb))
  diffs = [i for i in range(n) if ra[i] != fb[i]]
  print(f"\nREVERSED-A vs B: {n} rows compared, {len(diffs)} DIFFER")
  for i in diffs[:20]:
    print(f"  ROW {i}:\n    A: {ra[i]}\n    B: {fb[i]}")
  if len(ra) != len(fb):
    print(f"  LENGTH DIFFERS: A={len(ra)} B={len(fb)}")
