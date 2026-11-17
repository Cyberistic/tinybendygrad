#!/usr/bin/env python3
"""**THE **ROWS' **STRUCTURE**, **FLATTENED **IN **CHRONOLOGICAL **ORDER**, **FOR **EITHER **LAYOUT**.

**THE **TWO **LAYOUTS **STORE **THE **ROWS **DIFFERENTLY** -- **⇒⇒⇒ AND **THE **PROBE **MUST **READ
**BOTH**:
  · **THE **OLD **LAYOUT**: `ts` **HOLDS **EVERY **BLOCK** (THE **NEWEST **FIRST) **⇒⇒⇒ AND **THE
    **ROWS **WITHIN **A **BLOCK **ARE **NEWEST-FIRST** **⇒⇒⇒ AND **SO **THE **CHRONOLOGICAL
    **ORDER **IS **EVERYTHING **REVERSED**.
  · **THE **NEW **LAYOUT**: `ts` **HOLDS **THE **COMPLETED **BLOCKS **ONLY** (OLDEST-FIRST, ROWS
    OLDEST-FIRST) **⇒⇒⇒ AND **THE **CURRENT **BLOCK **IS **A **SEPARATE **FIELD** (`cur`,
    NEWEST-FIRST) **⇒⇒⇒ AND **SO **THE **CHRONOLOGICAL **ORDER **IS **`ts` **AS **IS **THEN **`cur`
    **REVERSED**.

**⇒⇒⇒ AND **THE **PROBE **READS **THE **STRUCTURE **OUT **OF **THE **COMPILED **CODE**, **⇒⇒⇒ AND
**SO **IT **CAN **HANDLE **BOTH** -- **⇒⇒⇒ AND **THE **DIFF **IS **THE **DIRECTOR**.
"""

import json
import pathlib
import sys
import time

sys.path.insert(0, '.agents/slop/cpuseam')
sys.path.insert(0, '.agents/slop/cpuseam/builds')
import noisefloor  # noqa: E402

B = pathlib.Path('.agents/slop/cpuseam/builds')


def rows_of(xs):
  """**THE **ROWS **OF **A **LIST **OF **PIECES-LISTS**."""
  out = []
  while xs and xs.get("$") == "Con":
    out.append(xs["head"])
    xs = xs["tail"]
  return out


def instrument(js_path: pathlib.Path, out_path: pathlib.Path) -> pathlib.Path:
  src = js_path.read_text()
  # **⇒⇒⇒ AND **THE **PROBE **GOES **AT **THE **`Rows_blk` **SITE**, **⇒⇒⇒ AND **THE **`_r_0`** **IS
  # **THE **`Rows` **RECORD** -- **⇒⇒⇒ AND **`_r_0.ts`** **IS **THE **BLOCK **LIST** **AND
  # **`_r_0.cur`** **IS **THE **CURRENT **BLOCK** (WHEN **THE **LAYOUT **HAS **ONE**)**.
  name = "$_________tinybendygrad_renderer_cstyle_Rows_blk"
  site = f"function {name}("
  if src.count(site) != 1:
    raise SystemExit(f"WARN: the Rows_blk site is {src.count(site)}")
  i = src.index(site)
  b = src.index("{", i)
  # **⇒⇒⇒ AND **THE **PROBE **TAKES **THE **BLOCK **LIST **AND **THE **CURRENT **BLOCK**, **⇒⇒⇒ AND
  # **IT **RECORDS **THEM **AS **THE **CHRONOLOGICAL **ORDER** -- **⇒⇒⇒ AND **THE **TWO **ORDERS
  # **DIFFER**, **⇒⇒⇒ AND **SO **THE **PROBE **RECORD **BOTH **AND **THE **COMPARISON **USES
  # **THE **RIGHT **ONE**.
  probe = ('\n  { const __ls = []; let __x = _r_0.ts; '
           'while (__x && __x.$ === "Con") { const __rs = []; let __y = __x.head; '
           'while (__y && __y.$ === "Con") { const __ps = []; let __z = __y.head; '
           'while (__z && __z.$ === "Con") { __ps.push(__z.head); __z = __z.tail; } '
           '__rs.push(__ps); __y = __y.tail; } __ls.push(__rs); __x = __x.tail; } '
           'const __cur = (typeof _r_0.cur !== "undefined") ? _r_0.cur : null; '
           'if (globalThis.__RG) { globalThis.__RG.rows = __ls; globalThis.__RG.cur = __cur; '
           'globalThis.__RG.n += 1; } }')
  src = src[:b + 1] + probe + src[b + 1:]
  old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
  src = src.replace(old2, "globalThis.__RG = {rows: [], n: 0};\n" + old2, 1)
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
  out = B / f"rr_{tag}.js"
  instrument(js, out)
  d = noisefloor.Daemon(out, f"rr{tag}")
  d.start()
  time.sleep(0.8)
  d.turn()
  d.stop()
  R = json.loads((B.parent / f"nf-rr{tag}/cpu.json.d").read_text())
  blocks = R.get("rows", [])
  cur = R.get("cur")
  cur_rows = rows_of(cur) if cur else None
  return blocks, cur_rows


def chronological(blocks, cur_rows):
  """**THE **CHRONOLOGICAL **ORDER**: **THE **BLOCKS **AS **THEY **ARE** (OLDEST-FIRST) **AND **THE
  **CURRENT **BLOCK **REVERSED** (IT **IS **NEWEST-FIRST)** -- **⇒⇒⇒ AND **THE **OLD **LAYOUT
  **IS **THE **OTHER **WAY **ROUND**, **⇒⇒⇒ AND **SO **THE **CALLER **SAYS **WHICH**."""
  out = []
  for blk in blocks:
    out += blk
  if cur_rows:
    out += list(reversed(cur_rows))
  return out


if __name__ == "__main__":
  a = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else B / "base_now.js"
  b = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else B / "fwd4.js"
  ab, acur = dump(a, "a")
  bb, bcur = dump(b, "b")
  print(f"A {a.name}: {len(ab)} blocks, cur={len(acur) if acur is not None else 'NONE'}")
  print(f"B {b.name}: {len(bb)} blocks, cur={len(bcur) if bcur is not None else 'NONE'}")
  # **THE **OLD **LAYOUT**: EVERYTHING **REVERSED**.  **THE **NEW**: THE **BLOCKS **AS **IS** **AND
  # **THE **CURRENT **REVERSED**.
  A = []
  for blk in reversed(ab):
    A += list(reversed(blk))
  Bf = chronological(bb, bcur)
  n = min(len(A), len(Bf))
  d = [i for i in range(n) if A[i] != Bf[i]]
  print(f"\nA={len(A)} B={len(Bf)} DIFFS={len(d)}")
  for i in d[:12]:
    print(f"  ROW {i}: A={A[i]} B={Bf[i]}")
