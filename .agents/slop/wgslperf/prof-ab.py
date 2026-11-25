#!/usr/bin/env python3
"""**THE **V8 **CPU **PROFILE's **SAMPLE **COUNT, **HEAD **AND **THE **TREE, **ALTERNATED.**

**WHY.** THE MACHINE IS SHARED (IT CARRIES OTHER PANES's WORK), SO THE WALL CLOCK IS NOISY. V8's
PROFILE SAMPLES THE PROCESS's OWN EXECUTION, AND THE SAMPLE COUNT IS PROPORTIONAL TO THE CPU
TIME THE TURN BURNED, SO IT IS THE READING THAT SURVIVES THE NOISE. THE TREE's OWN RULE: A COUNT
WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A MEASUREMENT.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/prof-ab.py [N]`

**THE **BUILDs **ARE **BOTH **FRESH**: THE BASELINE IS A COPY OF `tinybendygrad/` WITH EVERY
TOUCHED FILE PUT BACK TO `HEAD`.
"""

import json
import pathlib
import shutil
import statistics
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"
BEND = R / "bin/bend"
PROF = HERE / "prof"


def build(driver: pathlib.Path, out: pathlib.Path):
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: {driver.name} did not build:\n{b.stderr[:1500]}")


def samples(js: pathlib.Path):
  PROF.mkdir(exist_ok=True)
  for old in PROF.glob("*.cpuprofile"):
    old.unlink()
  driver = HERE / "prof.run.mjs"
  driver.write_text('import M from "./' + js.name + '";\nM["chain_wgsl"]();\n')
  r = subprocess.run(["node", "--cpu-prof", "--cpu-prof-dir", str(PROF), str(driver)],
                     capture_output=True, text=True, cwd=str(HERE))
  if r.returncode != 0:
    print(r.stderr[:1200])
    raise SystemExit("WARN: the driver did not run")
  profs = sorted(PROF.glob("*.cpuprofile"))
  P = json.loads(profs[-1].read_text())
  return len(P["samples"])


def main():
  n = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3
  touched = [f for f in subprocess.run(["git", "diff", "--name-only", "HEAD"], capture_output=True,
                                       text=True, cwd=str(R)).stdout.split()
             if f.startswith("tinybendygrad/")]
  base_root = HERE / "baseline-tree"
  if base_root.exists():
    shutil.rmtree(base_root)
  shutil.copytree(R / "tinybendygrad", base_root)
  for f in touched:
    rel = f[len("tinybendygrad/"):]
    (base_root / rel).write_text(subprocess.run(["git", "show", f"HEAD:{f}"], capture_output=True,
                                                text=True, cwd=str(R)).stdout)
  driver = (HERE / "wgslprof.bend").read_text().replace("../../../../tinybendygrad/",
                                                        "../../baseline-tree/")
  (HERE / "wgslprof.base.bend").write_text(driver)
  build(HERE / "wgslprof.base.bend", HERE / "wgslprof.base.mjs")
  build(HERE / "wgslprof.bend", HERE / "wgslprof.bench.mjs")
  a, b = [], []
  for i in range(n):
    sa = samples(HERE / "wgslprof.base.mjs")
    sb = samples(HERE / "wgslprof.bench.mjs")
    a.append(sa)
    b.append(sb)
    print(f"  RUN {i + 1}: HEAD {sa} SAMPLES, THE TREE {sb} SAMPLES")
  print()
  print(f"{'HEAD':12s} THE MEDIAN {statistics.median(a):8.0f} SAMPLES  THE MIN {min(a)}")
  print(f"{'THE TREE':12s} THE MEDIAN {statistics.median(b):8.0f} SAMPLES  THE MIN {min(b)}")
  print()
  print(f"THE PROFILE: {statistics.median(a):.0f} -> {statistics.median(b):.0f} SAMPLES  "
        f"({100.0*(statistics.median(a)-statistics.median(b))/statistics.median(a):.1f}% FEWER)")


if __name__ == "__main__":
  main()
