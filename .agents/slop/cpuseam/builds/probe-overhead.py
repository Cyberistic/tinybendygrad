#!/usr/bin/env python3
"""**THE INSTRUMENT's OWN COST**, MEASURED, AND **STATED IN THE OUTPUT**.

**WHY:** THE TREE's OWN RULE (`AGENTS.md`, §136): "**A REST-ARGUMENTS WRAPPER IS NOT FREE**"
-- **MEASURED, WRAPPING SEVEN FUNCTIONS MOVED THE RENDER FROM 2.265 ms TO 3.494 ms, A 54%
INSTRUMENT OVERHEAD ON THE VERY THING BEING MEASURED**."

**⇒⇒⇒ SO AN INSTRUMENT THAT **ADDS** WRAPPERS **MUST REPORT **THE COST IT ADDS**, OR THE
READING IS **A NUMBER WITH NO SHAPE** -- **A NUMBER THAT IS MOSTLY THE INSTRUMENT.**

**AND THIS IS THE **SAME** COMPARISON §137's `apply-predicates.py` MAKES**: **THE SAME
PROGRAM, ONCE WITH THE CLOCKS AND ONCE WITHOUT**, AND **THE DIFFERENCE IS **THE INSTRUMENT**.

**AND THE VERDICT IS **THE RATIO OF THE TWO MINIMA**, BECAUSE **THE PORT's OWN COST IS **THE
FLOOR OF ITS OWN TIME** (VERDICT.PY).**
"""

import json
import pathlib
import statistics
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def clocked(js: pathlib.Path, out: pathlib.Path):
  """**THE RENDER's OWN WALL**, READ **INSIDE** THE DAEMON -- **THE SAME PATCH THE A/B
  USES**, SO THE TWO ARE **COMPARABLE**."""
  src = js.read_text()
  old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__C || (globalThis.__C = []);
      __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the render site is {src.count(old)}")
  src = src.replace(old, new, 1)
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__C || [])); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if src.count(dump_old) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(dump_old)}")
  src = src.replace(dump_old, dump_new, 1)
  out.write_text(src)
  return out


def read(js: pathlib.Path, tag: str, turns: int):
  """**THE RENDER's OWN WALL**, **A PER-TURN LIST**, FROM **THE DUMP**."""
  d = noisefloor.Daemon(js, tag)
  d.start()
  time.sleep(0.8)
  for _ in range(turns):
    d.turn()
  d.stop()
  f = BUILD.parent / f"nf-{tag}/cpu.json.d"
  rows = json.loads(f.read_text())
  return [r["w"] for r in rows]


if __name__ == "__main__":
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 60
  plain = BUILD / "now.js"
  shaped = BUILD / "serve_render.js"
  a = clocked(plain, BUILD / "ovh_a.js")
  b = clocked(shaped, BUILD / "ovh_b.js")
  ra = read(a, "ovh-a", turns)
  rb = read(b, "ovh-b", turns)
  print(f"\nTHE INSTRUMENT's OWN COST, ON **THE RENDER's OWN WALL** ({len(ra)} TURNS):")
  print(f"  WITHOUT THE INSTRUMENT   min {min(ra):.4f}  median {statistics.median(ra):.4f}")
  print(f"  WITH    THE INSTRUMENT   min {min(rb):.4f}  median {statistics.median(rb):.4f}")
  print(f"  THE RATIO OF THE MINIMA: {min(rb) / min(ra):.4f}")
  print(f"  **AND SO EVERY PART THE INSTRUMENT REPORTS IS **INFLATED BY ABOUT THAT FACTOR,**")
  print(f"  **AND THE PART NUMBERS ARE **RELATIVE** (WHICH IS CONTAINS WHAT) RATHER THAN")
  print(f"  **ABSOLUTE** (HOW MUCH).**")
