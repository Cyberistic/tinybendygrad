#!/usr/bin/env python3
"""PATCH **BOTH** BUILDS SO EACH REPORTS **ITS OWN** CPU TIME, AND A/B THEM.

**WHY THE CHILD's OWN CPU CLOCK AND NOT `RUSAGE_CHILDREN`:** MEASURED, `RUSAGE_CHILDREN` IS
**STALE UNTIL THE CHILD IS REAPED** — IT READ `(0.0, 0.0)` WHILE THE DAEMON WAS RUNNING, AND THE
NUMBERS ONLY APPEARED AFTER `p.kill(); p.wait()`. SO THE **INSTRUMENT HAS TO LIVE INSIDE
THE DAEMON**, AND IT IS **`process.cpuUsage()`**, WHICH IS THE **DAEMON's OWN** CPU TIME.

**AND THE CLOCK IS READ **AT THE `@@END`**, SO IT IS THE CPU OF **THE TURN**, NOT OF THE
WHOLE SESSION — AND THE **FIRST** TURN IS **WARMED** AND DROPPED, BECAUSE IT PAYS THE
JIT.

**AND THE TWO SIDES ARE **ALTERNATED** IN **ROUNDS**, SO A LOAD SPIKE HITS BOTH EQUALLY,
AND THE **MEDIAN** OF THE **PER-ROUND RATIOS** IS THE VERDICT.
"""

import json
import pathlib
import statistics
import subprocess
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
import portc  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"
WIRE = BUILD / "wire_now.txt"

# THE PATCH: THE `@@END` SITE IS WHERE **ONE TURN** ENDS, SO IT IS WHERE THE CLOCK IS READ.
PATCH_FROM = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
PATCH_TO = """    { const __u = process.cpuUsage(); const __c = globalThis.__C || (globalThis.__C = []);
      __c.push({u: __u.user, s: __u.system});
      try { require("fs").writeFileSync(process.env.__T_OUT || "/tmp/daemon-cpu.json", JSON.stringify(__c)); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""


def patched(js: pathlib.Path, out: pathlib.Path):
  src = js.read_text()
  if src.count(PATCH_FROM) != 1:
    raise SystemExit(f"WARN: {src.count(PATCH_FROM)} matches in {js}")
  out.write_text(src.replace(PATCH_FROM, PATCH_TO, 1))
  return out


class Daemon:
  def __init__(self, js: pathlib.Path, tag: str):
    self.dir = pathlib.Path(portc.OUT) / f"cpuprobe-{tag}"
    self.dir.mkdir(parents=True, exist_ok=True)
    self.fifo = self.dir / "sig.fifo"
    import os
    if self.fifo.exists():
      self.fifo.unlink()
    os.mkfifo(self.fifo)
    self.js = js
    self.proc = None
    self.q = None
    self.w = None
    self.frame = None
    self.cpu_file = self.dir / "cpu.json"

  def start(self):
    env = dict(portc.ENV)
    env["__T_OUT"] = str(self.cpu_file)
    self.proc = subprocess.Popen([str(portc.BUN), str(self.js), f"{self.fifo}|{self.dir}/req.wire"],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, bufsize=1, env=env)
    import queue
    import threading
    self.q = queue.Queue()
    threading.Thread(target=lambda: [self.q.put(l) for l in self.proc.stdout] + [self.q.put(None)],
                     daemon=True).start()
    self.w = open(self.fifo, "wb", buffering=0)
    wire = WIRE.read_text()
    self.frame = ("".join(f"{len(c):08d}{c}" for c in portc._chunks(wire)).encode() + b"00000000")

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

  def cpu(self):
    """THE DAEMON's OWN CPU TIME, **CUMULATIVE**, FROM ITS OWN FILE."""
    if not self.cpu_file.exists():
      return None
    try:
      json.loads(self.cpu_file.read_text())
    except Exception:
      return None
    rows = json.loads(self.cpu_file.read_text())
    if not rows:
      return None
    return (rows[-1]["u"] + rows[-1]["s"]) / 1000.0  # MS.

  def stop(self):
    if self.w:
      try:
        self.w.close()
      except Exception:
        pass
    if self.proc:
      self.proc.kill()
      self.proc.wait(timeout=5)


def measure(js: pathlib.Path, tag: str, turns: int):
  """THE CPU OF **ONE** BUILD, IN **ITS OWN** PROCESS, OVER `turns` TURNS."""
  d = Daemon(js, tag)
  if d.cpu_file.exists():
    d.cpu_file.unlink()
  d.start()
  time.sleep(0.8)
  d.turn()  # THE FIRST TURN PAYS THE JIT.
  c0 = d.cpu()
  for _ in range(turns):
    d.turn()
  c1 = d.cpu()
  out = d.turn()
  d.stop()
  return (c1 - c0) * 1000.0 / turns, out


if __name__ == "__main__":
  base = patched(BUILD / "serve_base.js", BUILD / "serve_base_cpu.js")
  new = patched(BUILD / "serve_fix.js", BUILD / "serve_fix_cpu.js")
  rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 8
  per = 10
  wa, wb, same = [], [], True
  for i in range(rounds):
    if i % 2:
      cp, c = measure(new, "new", per); wb.append(cp)
      cp, c2 = measure(base, "base", per); wa.append(cp)
    else:
      cp, c2 = measure(base, "base", per); wa.append(cp)
      cp, c = measure(new, "new", per); wb.append(cp)
    same = same and (c == c2)
  r = sorted(y / x for x, y in zip(wa, wb) if x > 0)
  print(f"base CPU ms/turn  median {statistics.median(wa):.4f}   rounds {len(wa)}")
  print(f"new  CPU ms/turn  median {statistics.median(wb):.4f}")
  print(f"CPU RATIO  min {r[0]:.4f}  median {statistics.median(r):.4f}  max {r[-1]:.4f}  "
        f"faster {sum(1 for x in r if x < 1.0)}/{len(r)}")
  print(f"same C: {same}")
