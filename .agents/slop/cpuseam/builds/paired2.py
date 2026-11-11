#!/usr/bin/env python3
"""THE **PAIRED** A/B: **TWO** DAEMONS, **ALTERNATED TURN BY TURN**, WITH THE **ROBUST** VERDICT.

****
**THE VERDICT IS THE **RATIO OF THE TWO MINIMA**, NOT THE MEDIAN OF THE PAIRED RATIOS.**
****
**MEASURED: THE **MEDIAN** OF THE PAIRED RATIO OF **THE **SAME** BUILD AGAINST **ITSELF** READS
**1.0249** ON A LOADED MACHINE -- **ABOVE ONE**, ON **IDENTICAL** BYTES. 
**SO A MEDIAN **CANNOT** DISTINGUISH A WIN FROM THE LOAD. **
**AND THE **MINIMUM** IS RIGHT BECAUSE THE PORT's OWN COST IS
**THE FLOOR OF ITS OWN TIME**: A TURN THAT RAN WHILE THE MACHINE WAS QUIET **IS** THE TURN, AND A
TURN THAT RAN WHILE THE MACHINE WAS BUSY IS **THE TURN PLUS THE WAIT**. **

**AND IT IS **A RATIO OF TWO MINIMA** AND NOT **A MINIMUM OF A
RATIO**, SO IT IS **THE SAME STATISTIC ON BOTH SIDES** -- AND THE MEDIAN IS REPORTED BESIDE IT, AND
**THE VERDICT IS THE WORSE OF THE TWO**, BECAUSE **A WIN THE LOAD MASKS IS NOT A WIN.**

**AND BOTH GATES ARE READ AT ONCE**, BECAUSE THEY ARE **THE SAME
CLAIM IN TWO UNITS**:
  · the **RENDER's OWN WALL** -- THE PORT's COST, AND **THE VERDICT** FOR A RENDER CHANGE.
  · the **DECODE's OWN WALL** -- FOR A CHANGE THAT IS **IN** THE DECODE.

**AND `same C` IS ASSERTED**: THE TWO DAEMONS MUST PRODUCE
**BYTE-IDENTICAL** OUTPUT, OR THE COMPARISON IS **NOT A COMPARISON** BUT **TWO DIFFERENT THINGS**.
"""

import json
import pathlib
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402
import verdict as V  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def clocked(js: pathlib.Path, out: pathlib.Path):
  """**THE RENDER's AND THE DECODE's OWN WALL**, READ **INSIDE** THE DAEMON."""
  src = js.read_text()
  old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__C || (globalThis.__C = []);
      __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  if src.count(old) != 1:
    raise SystemExit(f"paired: the render site is {src.count(old)}")
  src = src.replace(old, new, 1)
  old2 = """    return $IO_bind($$decode(_cs_1), run_clo($serve_c7(_f_0,_k_0)), _x_8);"""
  new2 = """    const __td = performance.now();
    return $IO_bind($$decode(_cs_1),
      (_x_9b) => { const __c = globalThis.__DC || (globalThis.__DC = []);
        __c.push({w: performance.now() - __td});
        return run_clo($serve_c7(_f_0,_k_0))(_x_9b); },
      _x_8);"""
  if src.count(old2) != 1:
    raise SystemExit(f"paired: the decode site is {src.count(old2)}")
  src = src.replace(old2, new2, 1)
  old3 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  new3 = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify({render: globalThis.__C || [], decode: globalThis.__DC || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(old3) != 1:
    raise SystemExit(f"paired: the @@END site is {src.count(old3)}")
  src = src.replace(old3, new3, 1)
  out.write_text(src)
  return out


def run(a_js: pathlib.Path, b_js: pathlib.Path, turns: int, tag: str = "ab"):
  """**TWO** DAEMONS, **ALTERNATED TURN BY TURN**, AND BOTH SIDES RUN **THE SAME** TURNS."""
  A = noisefloor.Daemon(a_js, f"{tag}-a")
  B = noisefloor.Daemon(b_js, f"{tag}-b")
  A.start()
  B.start()
  time.sleep(0.8)
  for _ in range(3):
    A.turn()
    B.turn()
  same = True
  for i in range(turns):
    if i % 2:
      ob = B.turn()
      oa = A.turn()
    else:
      oa = A.turn()
      ob = B.turn()
    same = same and (oa == ob)
  A.stop()
  B.stop()
  da = json.loads((BUILD.parent / f"nf-{tag}-a/cpu.json.d").read_text())
  db = json.loads((BUILD.parent / f"nf-{tag}-b/cpu.json.d").read_text())
  ra = [r["w"] for r in da["render"]]
  rb = [r["w"] for r in db["render"]]
  n = min(len(ra), len(rb))
  dc = [r["w"] for r in da["decode"]]
  dd = [r["w"] for r in db["decode"]]
  n2 = min(len(dc), len(dd))
  return ra[:n], rb[:n], dc[:n2], dd[:n2], same


if __name__ == "__main__":
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 120
  a_js = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else BUILD / "serve_base.js"
  b_js = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else BUILD / "serve_base.js"
  la = sys.argv[4] if len(sys.argv) > 4 else "A"
  lb = sys.argv[5] if len(sys.argv) > 5 else "B"
  out_a = BUILD / "ab_a.js"
  out_b = BUILD / "ab_b.js"
  clocked(a_js, out_a)
  clocked(b_js, out_b)
  ra, rb, dc, dd, same = run(out_a, out_b, turns)
  V.report(f"{la} (RENDER)", f"{lb} (RENDER)", ra, rb, same)
  V.report(f"{la} (DECODE)", f"{lb} (DECODE)", dc, dd, same)
