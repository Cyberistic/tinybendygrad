#!/usr/bin/env python3
"""DRIVE THE DAEMON AND REPORT THE PHASE BREAKDOWN, FROM CLOCKS **INSIDE** ITS OWN PROCESS.

WHY THE CLOCKS ARE INSIDE: THE `bun --cpu-prof` PROFILE ATTRIBUTES BLOCKING KERNEL TIME TO
THE NEAREST SYMBOL, AND A SYSCALL THAT BLOCKS WHILE THE SCHEDULER RUNS OTHER WORK IS SAMPLED AS
THE CALLER's FRAME. THE PROFILE's `fstatSync 18.6%` IS ITS OWN ATTRIBUTION, NOT THE PORT's
COST: MEASURED, `os.fstat` ON A FIFO IS **0.653 us**, SO THE PROFILER's "1.32 ms A fstatSync" IS
2,000x THE TRUTH AND IS THE POLLER's WAIT.

AND TWO TOOLING RULES THIS DRIVER ENFORCES, BOTH MEASURED THE HARD WAY:
  (1) **A BUILD IS A SECOND SOURCE OF TRUTH.** THE INSTRUMENT RUNS UNDER `bun` AND NOT UNDER THE
      COMPILED EXECUTABLE (`_serve_bin`'s CACHE NEVER REBUILDS, AND `bun build --compile --minify`
      RELOCATES `require("fs")` INTO A MODULE SCOPE WHERE THE PATCH IS NOT), AND **THE STALE `.bc`
      IS DELETED** BEFORE EVERY RUN.
  (2) **A REST-ARGUMENTS WRAPPER IS NOT FREE.** MEASURED, WRAPPING SEVEN FUNCTIONS IN
      `(...a) => f(...a)` MOVED THE RENDER FROM 2.265 ms TO 3.494 ms -- A 54% INSTRUMENT OVERHEAD ON
      THE VERY THING BEING MEASURED. SO THE CLOCKS ARE **INSIDE** THE FUNCTIONS AND NOT AROUND
      THEM, AND THE COUNTS ARE **INSIDE** THE FUNCTION BODIES AND NOT AT THE CALL SITES.
"""

import json
import pathlib
import statistics
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]  # `builds/` IS FOUR LEVELS BELOW THE ROOT.
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
import portc  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"
WIRE = BUILD / "wire_now.txt"
PHASE = BUILD / "daemon-phase.json"


def drive(js: pathlib.Path, turns: int, wire: str):
  """The tree's OWN worker, and the wire's own framing."""
  portc._serve_bin = lambda js: None  # NO STALE `.bc`, AND NO `--minify` RELOCATION.
  if PHASE.exists():
    PHASE.unlink()
  portc.OUT.mkdir(parents=True, exist_ok=True)
  w = portc.Worker(js, "phase")
  w.start()
  time.sleep(0.8)
  walls = []
  for _ in range(turns + 1):
    t0 = time.perf_counter()
    w.render(wire)
    walls.append((time.perf_counter() - t0) * 1e3)
  walls = walls[1:]  # THE FIRST TURN PAYS THE START-UP.
  w.stop()
  return walls


def report(js: pathlib.Path, turns: int = 40, wire: str = None):
  wire = wire if wire is not None else WIRE.read_text()
  walls = drive(js, turns, wire)
  T = json.loads(PHASE.read_text()) if PHASE.exists() else {}
  n = max(T.get("nturn", 1), 1)
  med = statistics.median(walls)
  print(f"caller's wall per turn      median {med:.4f} ms   min {min(walls):.4f}")
  for k in ("decode", "render", "walk", "one", "kern"):
    if k in T:
      print(f"  {k:8s} {T[k]/n:.4f} ms/turn")
  own = (T.get("decode", 0) + T.get("render", 0)) / n
  print(f" THE PORT's OWN SHARE: {own:.4f} ms = {100*own/med:.1f}% OF {med:.4f} ms")
  return walls, T, med


if __name__ == "__main__":
  report(pathlib.Path(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else 40)
