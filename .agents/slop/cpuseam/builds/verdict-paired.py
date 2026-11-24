#!/usr/bin/env python3
"""**THE **A/B **OF **A **RENDERER **CHANGE**, **IN **THE **DAEMON** -- **⇒⇒† AND **THE **VERDICT
**IS **A **RATIO **OF **THE **PAIRED **RUNs**, **AND **THE **NOISE **FLOOR **IS **READ **NOW**.

**THE **RULE.** **A **CHANGE **THAT **IS **NEUTRAL **OR **FAILS **THE **KEEPER **LINE **IS
**REVERTED** (⇒⇒† AND **THE **TREE's OWN RULE**)**. **THE **KEEPER **LINE **IS **0.97** (⇒⇒† AND
**AND **THE **NOISE **FLOOR **IS **READ **IMMEDIATELY **BEFORE **THE **VERDICT**, **⇒⇒† AND **AND
**IT **MOVES **WITH **THE **LOAD**)**.

**AND **THE **TWO **BUILDS **ARE **ALTERNATED **TURN **BY **TURN** (⇒⇒† AND **A **PAIRED **A/B**)**.
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

BUILD = R / ".agents/slop/cpuseam/builds"

WALL_OLD = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
WALL_NEW = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __c = globalThis.__W || (globalThis.__W = []); __c.push({w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
DUMP_OLD = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
DUMP_NEW = """    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".w",
        JSON.stringify({W: globalThis.__W || []})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""


def build(name: str, s: str) -> pathlib.Path:
  s = s.replace(WALL_OLD, WALL_NEW).replace(DUMP_OLD, DUMP_NEW)
  p = BUILD / name
  p.write_text(s)
  return p


def walls_of(tag: str):
  p = pathlib.Path(str(BUILD.parent / f"nf-{tag}" / "cpu.json") + ".w")
  return [w["w"] for w in json.loads(p.read_text()).get("W", [])]


def paired(a_path: pathlib.Path, b_path: pathlib.Path, tag_a: str, tag_b: str, turns: int = 50):
  """THE **PAIRED **RUN** -- **⇒⇒† AND **AND **THE **TWO **ARE **ALTERNATED**, **⇒⇒† AND **AND **THE
  **VERDICT **IS **THE **RATIO **OF **THE **TWO **MINIMA** (⇒⇒† AND **AND **THE **MEDIAN **OF **THE
  **PAIRED **RATIOS **IS **THE **SECOND **READING**)**.

  **⇒⇒† AND **THE **TURNS **ARE **A **COUNT **AND **NOT **A **DURATION** (⇒⇒† AND **AND **THE
  **MACHINE's **LOAD **MOVES**, **⇒⇒† AND **AND **A **VERDICT **ON **A **LOADED **MACHINE **NEEDS
  **MORE **SAMPLES**, **⇒⇒† AND **NOT **A **SHORTER **RUN**)**."""
  da = noisefloor.Daemon(a_path, tag_a)
  db = noisefloor.Daemon(b_path, tag_b)
  da.start()
  db.start()
  time.sleep(1.2)
  for _ in range(turns):
    da.turn()
    db.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()
  return walls_of(tag_a), walls_of(tag_b)


def verdict(a: list, b: list, label: str):
  A = sorted(a)
  B = sorted(b)
  print()
  print(f"THE **VERDICT **FOR **{label}**:")
  print("  A (the baseline): min %.4f  median %.4f   (n=%d)" % (A[0], A[len(A) // 2], len(A)))
  print("  B (the change):   min %.4f  median %.4f   (n=%d)" % (B[0], B[len(B) // 2], len(B)))
  print("  THE RATIO OF THE TWO MINIMA:  %.4f" % (B[0] / A[0]))
  print("  THE RATIO OF THE TWO MEDIANS: %.4f" % (B[len(B) // 2] / A[len(A) // 2]))
  # **⇒⇒† AND **THE **MEDIAN **OF **THE **PAIRED **RATIOS** (⇒⇒† AND **THE **SECOND **READING**)**.
  n = min(len(a), len(b))
  ratios = sorted(b[i] / a[i] for i in range(n))
  print("  THE MEDIAN OF THE PAIRED RATIOS: %.4f" % ratios[len(ratios) // 2])
  print("  THE WINS: %d of %d   (the KEEPER LINE IS 0.97)" % (sum(1 for r in ratios if r < 0.97), n))


def main():
  import sys as _s
  base = BUILD / (_s.argv[1] if len(_s.argv) > 1 else "serve_base.js")
  other = BUILD / (_s.argv[2] if len(_s.argv) > 2 else "serve_ab_base.js")
  a = build("serve_v_base.js", base.read_text())
  b = build("serve_v_new.js", other.read_text())
  turns = int(_s.argv[3]) if len(_s.argv) > 3 else 50
  # **⇒⇒† AND **THE **NOISE **FLOOR **IS **A **THIRD **ARM** (⇒⇒† AND **AND **THE **SAME **BUILD
  # **AGAINST **ITSELF**), **⇒⇒† AND **AND **IT **RUNS **IN **THE **SAME **INTERLEAVED **LOOP** (⇒⇒†
  # **AND **AND **SO **IT **READS **THE **SAME **LOAD** (⇒⇒† AND **AND **THE **VERDICT **IS **THEN
  # **AGAINST **THE **NOISE **AT **THE **SAME **MOMENT**, **⇒⇒† AND **AND **NOT **AGAINST **A
  # **SEPARATE **RUN**)**.
  #
  # **⇒⇒† AND **THE **ARM's **ORDER **IS **ROTATED** (⇒⇒† AND **AND **A **FIXED **ORDER **BIASES
  # **THE **FIRST **ARM** **AND **THE **LAST**) -- **⇒⇒† AND **AND **THE **THREE **ARMS **TAKE
  # **TURNS **IN **A **ROUND-ROBIN**)**.
  c = build("serve_v_noise.js", base.read_text())
  da = noisefloor.Daemon(a, "vbase")
  db = noisefloor.Daemon(b, "vnew")
  dc = noisefloor.Daemon(c, "vnoise")
  da.start()
  db.start()
  dc.start()
  time.sleep(1.2)
  for _ in range(turns):
    da.turn()
    db.turn()
    dc.turn()
  time.sleep(0.3)
  da.stop()
  db.stop()
  dc.stop()
  A = walls_of("vbase")
  B = walls_of("vnew")
  C = walls_of("vnoise")
  verdict(A, B, "THE CHANGE")
  # **⇒⇒† AND **THE **NOISE **FLOOR **IN **THE **SAME **LOOP** (⇒⇒† AND **AND **THE **SAME
  # **BUILD **AGAINST **ITSELF**)**
  verdict(A, C, "THE NOISE FLOOR (the SAME BUILD against ITSELF)")


if __name__ == "__main__":
  main()
