#!/usr/bin/env python3
"""THE **NOISE FLOOR**: THE **SAME** BUILD AGAINST **ITSELF**, **ALTERNATED TURN BY TURN**.

**WHY THIS FILE EXISTS**: THE MACHINE RUNS AT **LOAD AVERAGE 15–47** WITH OTHER UNITS'
PROCESSES AT **135%**, **56%**, **53%**, **51%** AND **47%**, AND MEASURED, THE WHOLE TURN's WALL
MEDIAN MOVED FROM **3.83 ms** TO **13.26 ms** ON THE **SAME** BUILD AND THE **SAME** WIRE. 
**SO A RATIO MEASURED AGAINST A **NOISY** MACHINE IS ONLY A CLAIM IF IT BEATS **THIS** NUMBER.**

AND THE MEASUREMENT IS **ALTERNATED TURN BY TURN**, BECAUSE A WHOLE-SIDE RUN IS **A
MEASUREMENT OF THE LOAD** AND AN ALTERNATED PAIR IS **A COMPARISON** (MEASURED, A WHOLE-SIDE RUN's
MEDIAN MOVED BY **2.4x** BETWEEN RUNS ON THE **SAME** BUILD).

**AND THE CLOCK IS **INSIDE** THE RENDER, SO IT IS **THE PORT's
WORK** AND NOT THE CALLER's WAIT.
"""

import json
import os
import pathlib
import queue
import statistics
import subprocess
import sys
import threading
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
import portc  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def clocked(js: pathlib.Path, out: pathlib.Path):
  """**THE RENDER's OWN WALL AND CPU**, READ **INSIDE** THE RENDER."""
  src = js.read_text()
  old = """    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  new = """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    { const __u = process.cpuUsage(globalThis.__PC); globalThis.__PC = __u;
      const __c = globalThis.__C || (globalThis.__C = []);
      __c.push({u: __u.user, s: __u.system, w: performance.now() - __t0}); }
    return $IO_bind((_x_11) => $IO_print(__r, _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);"""
  if src.count(old) != 1:
    raise SystemExit(f"WARN: the render site is {src.count(old)}")
  src = src.replace(old, new, 1)
  old2 = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  new2 = """    { try { require("fs").writeFileSync(process.env.__T_OUT || "/tmp/daemon-cpu.json", JSON.stringify(globalThis.__C || [])); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  if src.count(old2) != 1:
    raise SystemExit(f"WARN: the @@END site is {src.count(old2)}")
  src = src.replace(old2, new2, 1)
  out.write_text(src)
  return out


class Daemon:
  def __init__(self, js: pathlib.Path, tag: str):
    self.dir = BUILD.parent / f"nf-{tag}"
    self.dir.mkdir(parents=True, exist_ok=True)
    self.fifo = self.dir / "s"
    if self.fifo.exists():
      self.fifo.unlink()
    os.mkfifo(self.fifo)
    self.js = js
    self.cpu_file = self.dir / "cpu.json"
    self.proc = None
    self.q = None
    self.w = None
    self.frame = None

  def start(self):
    env = dict(portc.ENV)
    env["__T_OUT"] = str(self.cpu_file)
    self.proc = subprocess.Popen([str(portc.BUN), str(self.js), f"{self.fifo}|{self.dir}/req"],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, bufsize=1, env=env)
    self.q = queue.Queue()
    threading.Thread(target=self._pump, args=(self.q,), daemon=True).start()
    self.w = open(self.fifo, "wb", buffering=0)
    wire = (BUILD / "wire_now.txt").read_text()
    self.frame = ("".join(f"{len(c):08d}{c}" for c in portc._chunks(wire)).encode() + b"00000000")

  def _pump(self, q):
    for line in self.proc.stdout:
      q.put(line)
    q.put(None)

  def turn(self) -> str:
    self.w.write(self.frame)
    out, started = [], False
    while True:
      line = self.q.get(timeout=portc.TIMEOUT)
      if line is None:
        raise RuntimeError(f"the daemon exited: {self.proc.stderr.read()[:800]}")
      line = line.rstrip("\n")
      if line == "@@BEGIN":
        started = True
      elif line == "@@END" and started:
        return "\n".join(out)
      elif started:
        out.append(line)

  def rows(self):
    if not self.cpu_file.exists():
      return []
    try:
      return json.loads(self.cpu_file.read_text())
    except Exception:
      return []

  def stop(self):
    if self.w:
      try:
        self.w.close()
      except Exception:
        pass
    if self.proc:
      self.proc.kill()
      self.proc.wait(timeout=5)


def paired(a_js: pathlib.Path, b_js: pathlib.Path, turns: int = 60):
  """THE TWO DAEMONS ARE **ALTERNATED TURN BY TURN**, AND THE **PAIRED** RATIO IS THE VERDICT."""
  A, B = Daemon(a_js, "a"), Daemon(b_js, "b")
  A.start()
  B.start()
  time.sleep(0.8)
  for _ in range(3):
    A.turn()
    B.turn()
  wa, wb, ca, cb = [], [], [], []
  same = True
  oa = ob = None
  for i in range(turns):
    if i % 2:
      ob = B.turn()
      oa = A.turn()
    else:
      oa = A.turn()
      ob = B.turn()
    ra, rb = A.rows(), B.rows()
    if len(ra) > len(wa) and len(rb) > len(wb):
      wa.append(ra[-1]["w"])
      wb.append(rb[-1]["w"])
      ca.append((ra[-1]["u"] + ra[-1]["s"]) / 1000.0)
      cb.append((rb[-1]["u"] + rb[-1]["s"]) / 1000.0)
    same = same and (oa == ob)
  A.stop()
  B.stop()
  return wa, wb, ca, cb, same


if __name__ == "__main__":
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 60
  js = BUILD / "serve_base.js"
  a = clocked(js, BUILD / "nf_a.js")
  b = clocked(js, BUILD / "nf_b.js")
  wa, wb, ca, cb, same = paired(a, b, turns)
  r = sorted(y / x for x, y in zip(wa, wb) if x > 0)
  print(f"THE NOISE FLOOR: THE **SAME** BUILD AGAINST **ITSELF**, {len(r)} PAIRED TURNS")
  print(f"  the RENDER's wall: base {statistics.median(wa):.4f} ms   the SAME BUILD {statistics.median(wb):.4f} ms")
  print(f"  RATIO  min {r[0]:.4f}  p25 {r[len(r)//4]:.4f}  median {statistics.median(r):.4f}  max {r[-1]:.4f}")
  print(f" **A REAL IMPROVEMENT MUST BE **BELOW** THE **MEDIAN** OF THIS RATIO**.")
  print(f" AND THE **MINIMUM** IS THE **HONEST** FLOOR: {r[0]:.4f}.")
  rc = sorted(y / x for x, y in zip(ca, cb) if x > 0)
  print(f"  the RENDER's cpu: median {statistics.median(ca):.4f} vs {statistics.median(cb):.4f} ms   "
        f"RATIO median {statistics.median(rc):.4f}")
  print(f"  same C: {same}")
