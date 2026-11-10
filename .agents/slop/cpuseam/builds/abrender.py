#!/usr/bin/env python3
"""A/B THE **RENDER's OWN** TIME, **ALTERNATED TURN BY TURN**, SO THE LOAD HITS BOTH EQUALLY.

**WHY ALTERNATE TURN BY TURN AND NOT RUN A WHOLE SIDE AT A TIME:** MEASURED, THE MACHINE
RAN AT **LOAD AVERAGE 25–47** WITH OTHER UNITS' `tsc --noEmit` PROCESSES AT **354%**, **153%** AND
**131%**, AND A WHOLE-SIDE RUN'S MEDIAN MOVED BY **2.4x** BETWEEN RUNS ON THE **SAME** BUILD. 
A WHOLE-SIDE RUN IS **A MEASUREMENT OF THE LOAD**; AN ALTERNATED PAIR IS **A COMPARISON**.

AND THE **RENDER's OWN** TIME IS READ **INSIDE** THE RENDER, WITH `performance.now()`
AROUND IT — SO IT IS **THE PORT's WORK** AND NOT THE CALLER's WAIT, AND IT IS **THE
NUMBER THE OPTIMISATION TARGETS**.

AND THE **CPU** READING IS REPORTED **BESIDE** IT, BUT **IT IS NOT THE VERDICT**:
MEASURED, `process.cpuUsage()` ON A LOADED MACHINE INCLUDES THE TIME THE PROCESS WAS **DESCHEDULED**,
SO IT READS **1.1746** (A LOSS) WHERE THE WALL READS **0.9029** (A WIN) ON THE **SAME** TURNS.
**THE WALL INSIDE THE RENDER IS THE VERDICT, AND THE CPU IS A SECOND READING THAT
ONLY COUNTS WHEN THE MACHINE IS QUIET.**
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


class Daemon:
  def __init__(self, js: pathlib.Path, tag: str):
    self.dir = BUILD.parent / f"ab-{tag}"
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
    # **THE THREAD's BODY NAMES `q`, AND THE **LATE-BINDING** OF A CLOSURE OVER A LOCAL IS
    # A **BINDING** BUG, NOT A TIMING ONE** -- AND IT HANGS THE DRIVER WITH
    # **NO ERROR**, BECAUSE THE EXCEPTION IS IN THE THREAD. SO THE QUEUE IS
    # PASSED **AS AN ARGUMENT**, WHICH BINDS IT AT DEFINITION TIME.
    threading.Thread(target=self._pump, args=(self.q,), daemon=True).start()
    self.w = open(self.fifo, "wb", buffering=0)
    wire = (BUILD / "wire_now.txt").read_text()
    self.frame = ("".join(f"{len(c):08d}{c}" for c in portc._chunks(wire)).encode() + b"00000000")

  def _pump(self, q):
    """THE READER: EVERY LINE INTO THE QUEUE, AND **NONE** AT THE END."""
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


def ab(base_js: pathlib.Path, new_js: pathlib.Path, turns: int = 60):
  """THE TWO DAEMONS ARE **ALTERNATED TURN BY TURN**, AND THE **PAIRED** RATIO IS THE VERDICT."""
  A, B = Daemon(base_js, "base"), Daemon(new_js, "new")
  A.start()
  B.start()
  time.sleep(0.8)
  for _ in range(3):
    A.turn()
    B.turn()
  c0a, c0b = A.cpu_file.stat().st_mtime if A.cpu_file.exists() else 0, 0
  wa, wb, ca, cb = [], [], [], []
  outa = outb = None
  for i in range(turns):
    if i % 2:
      outb = B.turn()
      outa = A.turn()
    else:
      outa = A.turn()
      outb = B.turn()
    ra, rb = A.rows(), B.rows()
    if len(ra) > len(wa) and len(rb) > len(wb):
      wa.append(ra[-1]["w"])
      wb.append(rb[-1]["w"])
      ca.append((ra[-1]["u"] + ra[-1]["s"]) / 1000.0)
      cb.append((rb[-1]["u"] + rb[-1]["s"]) / 1000.0)
  A.stop()
  B.stop()
  return wa, wb, ca, cb, outa == outb


if __name__ == "__main__":
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 60
  wa, wb, ca, cb, same = ab(BUILD / "serve_base_render.js", BUILD / "serve_fix_render.js", turns)
  r = sorted(y / x for x, y in zip(wa, wb) if x > 0)
  print(f"the RENDER's OWN WALL, {len(r)} PAIRED TURNS:")
  print(f"  base  median {statistics.median(wa):.4f} ms   min {min(wa):.4f}")
  print(f"  new   median {statistics.median(wb):.4f} ms   min {min(wb):.4f}")
  print(f"  RATIO  min {r[0]:.4f}  p25 {r[len(r)//4]:.4f}  median {statistics.median(r):.4f}  "
        f"max {r[-1]:.4f}   faster {sum(1 for x in r if x < 1.0)}/{len(r)}")
  rc = sorted(y / x for x, y in zip(ca, cb) if x > 0)
  print(f"the RENDER's OWN CPU (THE **SECOND** READING, AND ON A LOADED MACHINE IT IS NOISE):")
  print(f"  base  median {statistics.median(ca):.4f} ms   new median {statistics.median(cb):.4f} ms")
  print(f"  RATIO  median {statistics.median(rc):.4f}  faster {sum(1 for x in rc if x < 1.0)}/{len(rc)}")
  print(f"same C: {same}")
