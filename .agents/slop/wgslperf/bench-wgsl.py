#!/usr/bin/env python3
"""**THE **WGSL **TURN, **TIMED **N **TIMES**, **THE **MEDIAN **AND **THE **MINIMUM.**

**WHY.** THE TREE's OWN RULE: A COUNT WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A MEASUREMENT,
AND A SINGLE RUN IS A COUNT WITH A LOT OF NOISE. THE TURN IS THE WHOLE `chain_wgsl()` CALL, WHICH
IS WHAT THE PAGE DOES.

**THE **COMMANDS.**
  `.venv/bin/python .agents/slop/wgslperf/bench-wgsl.py [N]`     -- build and time N RUNS.
  `.venv/bin/python .agents/slop/wgslperf/bench-wgsl.py [N] --sha` -- AND PRINT THE SHA256 OF
  THE WGSL, WHICH IS THE CORRECTNESS TOKEN: THE WGSL MUST BE BYTE-IDENTICAL.

**THE **BUILD **IS **ALWAYS **FRESH** (⇒⇒† AND **AND **A **STALE **BUILD **MEASURED **THE **OLD
**TREE** -- **⇒⇒† AND **AND **THAT **IS **THIS **INSTRUMENT's **OWN **LESSON**).
"""

import hashlib
import pathlib
import statistics
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents/slop/wgslperf"
BEND = R / "bin/bend"


def main():
  n = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 5
  sha = "--sha" in sys.argv
  out = HERE / "wgslprof.bench.mjs"
  b = subprocess.run([str(BEND), str(HERE / "wgslprof.bend"), "-o", str(out)],
                     capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1500]}")
  driver = HERE / "bench.run.mjs"
  driver.write_text('import M from "./wgslprof.bench.mjs";\n'
                    'const t0 = Date.now();\n'
                    'const w = M["chain_wgsl"]();\n'
                    'console.log((Date.now() - t0) + " " + w.length + " " + w);\n')
  times = []
  digest = ""
  for i in range(n):
    r = subprocess.run(["node", str(driver)], capture_output=True, text=True, cwd=str(HERE))
    if r.returncode != 0:
      print(r.stderr[:1500])
      raise SystemExit("WARN: the driver did not run")
    ms, ln, w = r.stdout.split(" ", 2)
    # **THE **DIGEST **IS **OVER **THE **WGSL **TEXT **AND **NOT **OVER **THE **LINE **THE
    # **DRIVER **PRINTED**: **`console.log` **ADDS **A **NEWLINE** (⇒⇒† AND **AND **THE **RECORD's
    # **SHA256 **IS **THE **TEXT **WITHOUT **IT**)**.
    if w.endswith("\n"):
      w = w[:-1]
    times.append(int(ms))
    digest = hashlib.sha256(w.encode()).hexdigest()
    print(f"  RUN {i + 1}: {ms} ms, {ln} bytes")
  print()
  print(f"THE TURN: THE MEDIAN {statistics.median(times)} ms, THE MIN {min(times)} ms, "
        f"THE MAX {max(times)} ms, OVER {n} RUNS")
  if sha:
    print(f"THE WGSL: {digest}")


if __name__ == "__main__":
  main()
