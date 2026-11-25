#!/usr/bin/env python3
"""**THE **WGSL **TURN, **TWO **TREES, **TIMED **THE **SAME **WAY, **ALTERNATED.**

**WHY.** THE MACHINE IS SHARED (IT CARRIES OTHER PANES's WORK), SO THE WALL CLOCK IS NOISY AND
THE TURN's COST IS READ AS THE **CPU **TIME** OF THE CHILD, WHICH IS WHAT THE TURN ACTUALLY BURNED.
THE TWO TREES ALTERNATE, SO A DRIFT IN THE MACHINE HITS BOTH.

**THE **COMMANDS.**
  `.venv/bin/python .agents/slop/wgslperf/bench-ab.py [N]`              -- HEAD vs THE TREE.
  `.venv/bin/python .agents/slop/wgslperf/bench-ab.py [N] --scratch`    -- HEAD vs A SCRATCH
  COPY OF THE TREE (⇒⇒† AND **AND **THAT **IS **WHERE **A **`fold.bend`** **CHANGE **IS **TESTED**).

**THE **CORRECTNESS **TOKEN**: THE SHA256 OF BOTH WGSL TEXTS, WHICH MUST BE THE SAME STRING.
"""

import hashlib
import pathlib
import resource
import statistics
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import wgslbase

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"


def run_once(js: pathlib.Path):
  driver = HERE / "bench.run.mjs"
  driver.write_text('import M from "./' + js.name + '";\n'
                    'const t0 = Date.now();\n'
                    'const w = M["chain_wgsl"]();\n'
                    'console.log((Date.now() - t0) + " " + w.length + " " + w);\n')
  before = resource.getrusage(resource.RUSAGE_CHILDREN)
  r = subprocess.run(["node", str(driver)], capture_output=True, text=True, cwd=str(HERE))
  after = resource.getrusage(resource.RUSAGE_CHILDREN)
  if r.returncode != 0:
    print(r.stderr[:1500])
    raise SystemExit("WARN: the driver did not run")
  ms, ln, w = r.stdout.split(" ", 2)
  # **THE **DIGEST **IS **OVER **THE **WGSL **TEXT **AND **NOT **OVER **THE **LINE **THE **DRIVER
  # **PRINTED**: **`console.log` **ADDS **A **NEWLINE** (⇒⇒† AND **AND **THE **RECORD's **SHA256
  # **IS **THE **TEXT **WITHOUT **IT**)**.
  if w.endswith("\n"):
    w = w[:-1]
  cpu = int((after.ru_utime - before.ru_utime) * 1000 + (after.ru_stime - before.ru_stime) * 1000)
  return int(ms), cpu, ln, hashlib.sha256(w.encode()).hexdigest()


def bench_pair(a_js: pathlib.Path, b_js: pathlib.Path, n: int):
  a, b, ca, cb = [], [], [], []
  for i in range(n):
    ms, cpu, _, da = run_once(a_js)
    a.append(ms)
    ca.append(cpu)
    ms, cpu, _, db = run_once(b_js)
    b.append(ms)
    cb.append(cpu)
    print(f"  RUN {i + 1}: A {a[-1]} ms / {ca[-1]} ms CPU, B {b[-1]} ms / {cb[-1]} ms CPU")
  print()
  print(f"{'A':12s} THE WALL MEDIAN {statistics.median(a):7} ms  THE MIN {min(a):7} ms  |  "
        f"THE CPU MEDIAN {statistics.median(ca):7} ms  THE MIN {min(ca):7} ms   THE WGSL {da}")
  print(f"{'B':12s} THE WALL MEDIAN {statistics.median(b):7} ms  THE MIN {min(b):7} ms  |  "
        f"THE CPU MEDIAN {statistics.median(cb):7} ms  THE MIN {min(cb):7} ms   THE WGSL {db}")
  return statistics.median(a), da, statistics.median(b), db, statistics.median(ca), statistics.median(cb)


def main():
  n = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 5
  scratch = "--scratch" in sys.argv
  base = sys.argv[sys.argv.index("--base") + 1] if "--base" in sys.argv else "HEAD"
  base_port = wgslbase.head_port("baseline", base)
  base_driver = wgslbase.bundle("baseline", base_port)
  if scratch:
    # **⇒⇒† AND **THE **SCRATCH **TREE **IS **THE **UNIT's **OWN**, **⇒⇒† AND **AND **IT **IS **NOT
    # **RECREATED **HERE** (⇒⇒† AND **AND **RECREATING **IT **WOULD **WIPE **THE **EDIT **UNDER
    # **TEST**)**.
    cand_port = HERE / "scratch" / "tinybendygrad"
    if not cand_port.exists():
      raise SystemExit("WARN: there is no scratch tree -- run `wgslbase.tree_port('scratch')` first")
    label = "SCRATCH"
  else:
    cand_port = wgslbase.tree_port("candidate")
    label = "THE TREE"
  cand_driver = wgslbase.bundle("scratch" if scratch else "candidate", cand_port)
  wgslbase.build(base_driver, HERE / "wgslprof.base.mjs")
  wgslbase.build(cand_driver, HERE / "wgslprof.cand.mjs")
  if (HERE / "wgslprof.base.mjs").read_text() == (HERE / "wgslprof.cand.mjs").read_text():
    raise SystemExit("WARN: THE TWO BUILDS ARE THE SAME BYTES -- the A/B WOULD COMPARE A THING "
                     "WITH ITSELF")
  print()
  b = bench_pair(HERE / "wgslprof.base.mjs", HERE / "wgslprof.cand.mjs", n)
  print()
  print(f"THE TURN: {b[0]:.0f} ms -> {b[2]:.0f} ms OF WALL ({100.0*(b[0]-b[2])/b[0]:.1f}%), "
        f"AND {b[4]:.0f} ms -> {b[5]:.0f} ms OF CPU ({100.0*(b[4]-b[5])/b[4]:.1f}%)")
  print(f"THE WGSL (HEAD vs {label}): "
        + ("BYTE-IDENTICAL" if b[1] == b[3] else "DIFFERS -- A CORRECTNESS DEFECT"))


if __name__ == "__main__":
  main()
