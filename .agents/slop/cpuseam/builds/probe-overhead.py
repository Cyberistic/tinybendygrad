#!/usr/bin/env python3
"""**THE INSTRUMENT's OWN COST**, MEASURED **PAIRED**, AND **THE PARTS' TRUE VALUES**.

**WHY THIS FILE EXISTS.** `render-shape.py` ADDS **WRAPPERS**, AND **A WRAPPER IS NOT FREE**
(THE TREE's OWN RULE, §136: WRAPPING SEVEN FUNCTIONS MOVED THE RENDER **2.265 ms -> 3.494 ms**).
**⇒⇒⇒ SO EVERY PART IT REPORTS IS **INFLATED**, AND **AN INSTRUMENT THAT REPORTS **AN
INFLATED NUMBER** WITHOUT SAYING **HOW MUCH** IS **A NUMBER WITH NO SHAPE**.**

**⇒⇒⇒ AND THE INFLATION IS **NOT UNIFORM** -- BECAUSE **THE PARTS ARE **NESTED** AND **THE
WRAPPERS ARE **ON THE LEAVES**, SO **THE DEEPER A PART IS, **THE MORE WRAPPER LAYERS IT
PAYs** ON THE WAY OUT. **⇒⇒⇒ AND **THE INFLATION IS **NOT A CONSTANT** EITHER, BECAUSE **THE
WRAPPER's COST DEPENDS ON **HOW MANY TIMES THE FUNCTION IS CALLED**.

**⇒⇒⇒ SO **THE ONLY HONEST FORM** IS: **THE SAME WORKLOAD, ON THE SAME CLOCK, IN THE SAME
PROCESS, WITH AND WITHOUT THE INSTRUMENT** -- AND **THE VERDICT IS **THE RATIO OF THE TWO
MINIMA** (VERDICT.PY: "**THE PORT's OWN COST IS **THE FLOOR OF ITS OWN TIME**").

**AND THE TWO SIDES ARE **ALTERNATED TURN BY TURN**, BECAUSE **A WHOLE-SIDE RUN IS **A
MEASUREMENT OF THE LOAD** AND AN ALTERNATED PAIR IS **A COMPARISON**.

**AND THE PARTS' TRUE VALUES ARE **THE SHAPED READING DIVIDED BY **THE INFLATION FACTOR** --
WHICH IS AN **ESTIMATE**, AND **IT IS LABELLED AS ONE**, BECAUSE **THE FACTOR IS **ONE NUMBER
FOR NESTED PARTS** AND **THE TRUE INFLATION IS **PER PART**.
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


def run(a_js: pathlib.Path, b_js: pathlib.Path, turns: int, tag: str):
  """**TWO** DAEMONS, **ALTERNATED TURN BY TURN**, AND **THE SAME** OUTPUTS."""
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
  # **THE TWO DUMP SHAPES**: THE PLAIN BUILD DUMPS **A LIST**, AND THE SHAPED ONE DUMPS
  # **AN OBJECT** WITH `W` IN IT.
  wa = [r["w"] for r in da] if isinstance(da, list) else [r["w"] for r in da.get("W", [])]
  wb = [r["w"] for r in db] if isinstance(db, list) else [r["w"] for r in db.get("W", [])]
  parts = db.get("R", {}) if isinstance(db, dict) else {}
  n = min(len(wa), len(wb))
  return wa[:n], wb[:n], parts, same


if __name__ == "__main__":
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 80
  plain = BUILD / "now.js"
  shaped = BUILD / "serve_render.js"
  # **THE PLAIN BUILD IS CLOCKED HERE**, AND **THE SHAPED BUILD ALREADY CARRIES **ITS OWN**
  # RENDER CLOCK** (`render-shape.py` PATCHES IT INTO `__W`) -- **SO IT IS **NOT** RE-CLOCKED,
  # AND **THAT IS CORRECT** BECAUSE **BOTH** ARE **THE SAME CLOCK AT THE SAME SITE**:
  # **THE SHAPED BUILD's CLOCK IS **INSIDE** THE RENDER, AND **SO IS THE PLAIN's**.
  a = clocked(plain, BUILD / "ovh_a.js")
  b = shaped
  wa, wb, parts, same = run(a, b, turns, "ovh")
  print(f"\nTHE INSTRUMENT's OWN COST, **PAIRED** ({len(wa)} PAIRED TURNS), same C: {same}")
  print(f"  WITHOUT (THE PLAIN BUILD)   min {min(wa):.4f}  p25 {sorted(wa)[len(wa) // 4]:.4f}  median {statistics.median(wa):.4f}")
  print(f"  WITH    (THE SHAPED BUILD)  min {min(wb):.4f}  p25 {sorted(wb)[len(wb) // 4]:.4f}  median {statistics.median(wb):.4f}")
  ratio = min(wb) / min(wa)
  print(f"\n  **THE INFLATION FACTOR: {ratio:.4f}** (THE RATIO OF THE TWO MINIMA)")
  n = max(parts.get("n", 1), 1)
  print(f"\nAND **THE PARTS' TRUE VALUES** (THE SHAPED READING DIVIDED BY **THE FACTOR**):")
  print("  **⇒⇒⇒ AND THIS IS AN **ESTIMATE**, BECAUSE **THE FACTOR IS **ONE NUMBER** AND")
  print("  **THE TRUE INFLATION IS **PER PART** (THE PARTS ARE **NESTED**).**")
  for k in ("named", "emit", "stmt", "alu", "decl", "strip"):
    if k in parts:
      shaped_v = parts[k] / n
      print(f"  {k:8s} shaped {shaped_v:.4f}   ESTIMATED TRUE {shaped_v / ratio:.4f} ms")
