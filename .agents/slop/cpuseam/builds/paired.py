#!/usr/bin/env python3
"""THE **PAIRED** A/B: **TWO** DAEMONS, **ALTERNATED TURN BY TURN**.

****
**THE VERDICT IS THE **PAIRED** RATIO**, BECAUSE A WHOLE-SIDE RUN IS **A MEASUREMENT OF THE
LOAD** AND AN ALTERNATED PAIR IS **A COMPARISON** (MEASURED: A WHOLE-SIDE RUN's MEDIAN MOVED BY
**2.4x** BETWEEN RUNS ON THE **SAME** BUILD WHILE THE MACHINE WAS AT LOAD 20–47).

****
**AND TWO GATES ARE READ AT ONCE**, BECAUSE THEY ARE THE **SAME CLAIM** IN TWO UNITS:
  · the **RENDER's OWN WALL** -- THE PORT's COST, AND **THE VERDICT**.
  · the **DECODE's OWN WALL** -- FOR THE CHANGE THAT IS **IN** THE DECODE.

****
**AND `same C` IS ASSERTED**: THE TWO DAEMONS MUST PRODUCE **BYTE-IDENTICAL** OUTPUT, OR
THE COMPARISON IS **NOT A COMPARISON** BUT **TWO DIFFERENT THINGS**.
"""

import json
import os
import pathlib
import statistics
import subprocess
import sys
import threading
import time
import queue

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def clocked(js: pathlib.Path, out: pathlib.Path):
  """**THE RENDER's AND THE DECODE's OWN WALL**, READ **INSIDE** THE DAEMON."""
  src = js.read_text()
  # THE RENDER.
  old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__C || (globalThis.__C = []);
      __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the render site is {src.count(old)}")
  src = src.replace(old, new, 1)
  # THE DECODE.
  old2 = """    return $IO_bind($$decode(_cs_1), run_clo($serve_c7(_f_0,_k_0)), _x_8);"""
  new2 = """    const __td = performance.now();
    return $IO_bind($$decode(_cs_1),
      (_x_9b) => { const __c = globalThis.__DC || (globalThis.__DC = []);
        __c.push({w: performance.now() - __td});
        return run_clo($serve_c7(_f_0,_k_0))(_x_9b); },
      _x_8);"""
  if src.count(old2) != 1:
    raise SystemExit(f"WARN: the decode site is {src.count(old2)}")
  src = src.replace(old2, new2, 1)
  # THE DUMP.
  old3 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  new3 = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify({render: globalThis.__C || [], decode: globalThis.__DC || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  if src.count(old3) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(old3)}")
  src = src.replace(old3, new3, 1)
  out.write_text(src)
  return out


class Paired:
  """**TWO** DAEMONS, **ALTERNATED TURN BY TURN**, AND THE **PAIRED** RATIO IS THE VERDICT."""

  def __init__(self, a_js: pathlib.Path, b_js: pathlib.Path, tag: str = "ab"):
    self.A = noisefloor.Daemon(a_js, f"{tag}-a")
    self.B = noisefloor.Daemon(b_js, f"{tag}-b")
    self.a_rows = []
    self.b_rows = []

  def run(self, turns: int):
    self.A.start()
    self.B.start()
    time.sleep(0.8)
    for _ in range(3):
      self.A.turn()
      self.B.turn()
    same = True
    for i in range(turns):
      if i % 2:
        ob = self.B.turn()
        oa = self.A.turn()
      else:
        oa = self.A.turn()
        ob = self.B.turn()
      ra, rb = self.A.rows(), self.B.rows()
      if len(ra) > len(self.a_rows) and len(rb) > len(self.b_rows):
        self.a_rows.append(ra[-1])
        self.b_rows.append(rb[-1])
      same = same and (oa == ob)
    self.A.stop()
    self.B.stop()
    return same


def report(label_a: str, label_b: str, rows_a, rows_b, same: bool):
  """**THE VERDICT**: THE **PAIRED** RATIO, AND **THE NOISE FLOOR** TO BEAT."""
  print(f"\n{'=' * 74}\nTHE PAIRED A/B: **{label_a}** vs **{label_b}**   ({len(rows_a)} PAIRED TURNS)")
  print(f"  same C: {same}")
  if not same:
    print(" **THE OUTPUTS DIFFER, SO THIS IS **NOT** A COMPARISON.**")
    return
  for name, key in (("RENDER", "w"), ("DECODE", "w")):
    a = [r[key] for r in rows_a]
    b = [r[key] for r in rows_b]
    ratios = sorted(y / x for x, y in zip(a, b) if x > 0)
    print(f"\n  THE {name}: A {statistics.median(a):.4f} ms   B {statistics.median(b):.4f} ms")
    print(f"    RATIO  min {ratios[0]:.4f}  p25 {ratios[len(ratios)//4]:.4f}  "
          f"median {statistics.median(ratios):.4f}  max {ratios[-1]:.4f}")
    print(f" **THE **MEDIAN** RATIO IS THE VERDICT, AND IT MUST BE **BELOW 0.9957**"
          f" (THE NOISE FLOOR, MEASURED).")
    print(f" **AND BELOW **0.97** (THE KEEPER LINE).**")


def _load(js: pathlib.Path):
  """THE TWO CLOCKED BUILDS' ROWS, FROM THE DUMP."""
  return []


if __name__ == "__main__":
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 100
  a_js = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else BUILD / "serve_base.js"
  b_js = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else BUILD / "serve_base.js"
  la = sys.argv[4] if len(sys.argv) > 4 else "A"
  lb = sys.argv[5] if len(sys.argv) > 5 else "B"
  out_a = BUILD / "ab_a.js"
  out_b = BUILD / "ab_b.js"
  clocked(a_js, out_a)
  clocked(b_js, out_b)
  p = Paired(out_a, out_b)
  same = p.run(turns)
  # THE DUMPS ARE **PER DAEMON** -- READ THEM AFTER THE STOP.
  da = json.loads((BUILD.parent / "nf-ab-a/cpu.json.d").read_text())
  db = json.loads((BUILD.parent / "nf-ab-b/cpu.json.d").read_text())
  ra, rb = da["render"], db["render"]
  da2, db2 = da["decode"], db["decode"]
  n = min(len(ra), len(rb))
  report(la, lb, [{"w": ra[i]["w"]} for i in range(n)], [{"w": rb[i]["w"]} for i in range(n)], same)
  n2 = min(len(da2), len(db2))
  report(f"{la} (decode)", f"{lb} (decode)", [{"w": da2[i]["w"]} for i in range(n2)],
         [{"w": db2[i]["w"]} for i in range(n2)], same)
