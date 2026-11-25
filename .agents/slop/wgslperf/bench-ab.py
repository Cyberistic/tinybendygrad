#!/usr/bin/env python3
"""**THE **WGSL **TURN, **THE **WORKING **TREE **AND **HEAD, **TIMED **THE **SAME **WAY.**

**WHY.** A NUMBER MEASURED AGAINST A NUMBER FROM ANOTHER SESSION IS NOT A MEASUREMENT, IT IS A
MEMORY. THIS BUILDS BOTH TREES NOW AND TIMES BOTH NOW, ON THE SAME MACHINE, WITH THE SAME
DRIVER, AND PRINTS THE SHA256 OF BOTH WGSL TEXTS, WHICH IS THE CORRECTNESS TOKEN: THE TWO MUST
BE THE SAME STRING.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/bench-ab.py [N]`

**THE **BASELINE **IS **HEAD**: A COPY OF `tinybendygrad/` WITH EVERY FILE THE WORKING TREE
TOUCHED PUT BACK TO `HEAD`, SO THE ONLY DIFFERENCE IS THE CHANGE UNDER TEST.
"""

import hashlib
import pathlib
import resource
import shutil
import subprocess
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import wgslbase

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"
BEND = R / "bin/bend"


def head_files():
  """**THE **FILES **THE **WORKING **TREE **TOUCHED**, **AND **THEIR **HEAD **VERSIONS**."""
  out = subprocess.run(["git", "diff", "--name-only", "HEAD"], capture_output=True, text=True,
                       cwd=str(R)).stdout.split()
  return [f for f in out if f.startswith("tinybendygrad/")]


def build(driver: pathlib.Path, out: pathlib.Path):
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1500]}")


def run_once(js: pathlib.Path, driver: pathlib.Path):
  driver.write_text('import M from "./' + js.name + '";\n'
                    'const t0 = Date.now();\n'
                    'const w = M["chain_wgsl"]();\n'
                    'console.log((Date.now() - t0) + " " + w.length + " " + w);\n')
  # **THE **CPU **TIME **OF **THE **CHILD**, **NOT **THE **WALL **CLOCK**: THE MACHINE IS
  # SHARED, SO THE WALL CLOCK IS THE OTHER PANES's NOISE, AND THE CPU TIME IS WHAT THE TURN
  # ACTUALLY COST.
  before = resource.getrusage(resource.RUSAGE_CHILDREN)
  r = subprocess.run(["node", str(driver)], capture_output=True, text=True, cwd=str(HERE))
  after = resource.getrusage(resource.RUSAGE_CHILDREN)
  if r.returncode != 0:
    print(r.stderr[:1500])
    raise SystemExit("WARN: the driver did not run")
  ms, ln, w = r.stdout.split(" ", 2)
  cpu = int((after.ru_utime - before.ru_utime) * 1000 + (after.ru_stime - before.ru_stime) * 1000)
  return int(ms), cpu, ln, hashlib.sha256(w.encode()).hexdigest()


def bench(label: str, js: pathlib.Path, n: int):
  times = []
  digest = ""
  for _ in range(n):
    ms, ln, digest = run_once(js, HERE / "bench.run.mjs")
    times.append(ms)
  print(f"{label:12s} THE MEDIAN {statistics.median(times):7} ms  THE MIN {min(times):7} ms  "
        f"THE MAX {max(times):7} ms   THE WGSL {digest}")
  return statistics.median(times), digest


def bench_pair(a_js: pathlib.Path, b_js: pathlib.Path, n: int):
  """**THE **TWO **TREES **ALTERNATE**, **SO **A **DRIFT **IN **THE **MACHINE **HITS **BOTH**."""
  a, b = [], []
  ca, cb = [], []
  for i in range(n):
    ms, cpu, _, da = run_once(a_js, HERE / "bench.run.mjs")
    a.append(ms)
    ca.append(cpu)
    ms, cpu, _, db = run_once(b_js, HERE / "bench.run.mjs")
    b.append(ms)
    cb.append(cpu)
    print(f"  RUN {i + 1}: HEAD {a[-1]} ms / {ca[-1]} ms CPU, THE TREE {b[-1]} ms / {cb[-1]} ms CPU")
  print()
  print(f"{'HEAD':12s} THE WALL MEDIAN {statistics.median(a):7} ms  THE MIN {min(a):7} ms  |  "
        f"THE CPU MEDIAN {statistics.median(ca):7} ms  THE MIN {min(ca):7} ms   THE WGSL {da}")
  print(f"{'THE TREE':12s} THE WALL MEDIAN {statistics.median(b):7} ms  THE MIN {min(b):7} ms  |  "
        f"THE CPU MEDIAN {statistics.median(cb):7} ms  THE MIN {min(cb):7} ms   THE WGSL {db}")
  return statistics.median(a), da, statistics.median(b), db, statistics.median(ca), statistics.median(cb)


def main():
  n = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 5
  touched = head_files()
  print("THE FILES THE WORKING TREE TOUCHED:", ", ".join(touched) or "(none)")
  base_root = HERE / "baseline-tree"
  base_driver = wgslbase.build_base()
  wgslbase.build(base_driver, HERE / "wgslprof.base.mjs")
  wgslbase.build(HERE / "wgslprof.bend", HERE / "wgslprof.bench.mjs")
  if (HERE / "wgslprof.base.mjs").read_text() == (HERE / "wgslprof.bench.mjs").read_text():
    raise SystemExit("WARN: THE TWO BUILDS ARE THE SAME BYTES -- the A/B WOULD COMPARE A THING "
                     "WITH ITSELF")
  print()
  b = bench_pair(HERE / "wgslprof.base.mjs", HERE / "wgslprof.bench.mjs", n)
  print()
  print(f"THE TURN: {b[0]:.0f} ms -> {b[2]:.0f} ms OF WALL ({100.0*(b[0]-b[2])/b[0]:.1f}%), "
        f"AND {b[4]:.0f} ms -> {b[5]:.0f} ms OF CPU ({100.0*(b[4]-b[5])/b[4]:.1f}%)")
  print("THE WGSL: " + ("BYTE-IDENTICAL" if b[1] == b[3] else "DIFFERS -- A CORRECTNESS DEFECT"))


if __name__ == "__main__":
  main()
